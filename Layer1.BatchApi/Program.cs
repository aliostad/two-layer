using Datadog.Trace;
using System.Net.Http.Json;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.Configure<BatchProcessingOptions>(builder.Configuration.GetSection("BatchProcessing"));

builder.Services.AddHttpClient<Layer2Client>((serviceProvider, client) =>
{
    var baseUrl = serviceProvider.GetRequiredService<IConfiguration>()["Layer2:BaseUrl"];
    if (string.IsNullOrWhiteSpace(baseUrl))
    {
        throw new InvalidOperationException("Configuration key 'Layer2:BaseUrl' is required.");
    }

    client.BaseAddress = new Uri(baseUrl);
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

app.MapPost("/api/batch/process", async (
    BatchRequest request,
    Layer2Client layer2Client,
    IOptions<BatchProcessingOptions> options,
    CancellationToken cancellationToken) =>
{
    if (request.Items.Count == 0)
    {
        return Results.BadRequest(new { message = "Batch must contain at least one item." });
    }

    if (request.Items.Count > 100)
    {
        return Results.BadRequest(new { message = "Batch can contain at most 100 items." });
    }

    var maxParallelism = Math.Clamp(options.Value.MaxParallelism, 1, 100);
    var results = new BatchItemResult[request.Items.Count];

    using var gate = new SemaphoreSlim(maxParallelism);

    var tasks = request.Items
        .Select((item, index) => ProcessItemAsync(item, index, layer2Client, gate, results, cancellationToken))
        .ToArray();

    await Task.WhenAll(tasks);

    var succeeded = results.Count(result => result.Status == BatchItemStatus.Succeeded);
    var failed = results.Length - succeeded;

    return Results.Ok(new BatchResponse(
        Guid.NewGuid().ToString("N"),
        request.Items.Count,
        succeeded,
        failed,
        results));
})
.WithName("ProcessBatch");

app.Run();

static async Task ProcessItemAsync(
    BatchItem item,
    int index,
    Layer2Client layer2Client,
    SemaphoreSlim gate,
    BatchItemResult[] results,
    CancellationToken cancellationToken)
{
    await gate.WaitAsync(cancellationToken);

    try
    {
        using var scope = Tracer.Instance.StartActive("batch.process_item");
        scope.Span.ResourceName = $"item:{item.Operation}";
        scope.Span.SetTag("batch.item.id", item.Id);
        scope.Span.SetTag("batch.item.operation", item.Operation);

        if (string.IsNullOrWhiteSpace(item.Operation))
        {
            results[index] = new BatchItemResult(item.Id, item.Operation, BatchItemStatus.Failed, null, "Operation is required.");
            return;
        }

        var simulation = await layer2Client.SimulateAsync(item.Operation, cancellationToken);
        results[index] = new BatchItemResult(item.Id, item.Operation, BatchItemStatus.Succeeded, simulation.DelayMs, null);
    }
    catch (Layer2ValidationException exception)
    {
        results[index] = new BatchItemResult(item.Id, item.Operation, BatchItemStatus.Failed, null, exception.Message);
    }
    catch (HttpRequestException exception)
    {
        results[index] = new BatchItemResult(item.Id, item.Operation, BatchItemStatus.Failed, null, $"Layer2 request failed: {exception.Message}");
    }
    finally
    {
        gate.Release();
    }
}

internal sealed record BatchRequest(IReadOnlyList<BatchItem> Items);

internal sealed record BatchItem(string Id, string Operation);

internal sealed record BatchResponse(
    string RequestId,
    int TotalItems,
    int Succeeded,
    int Failed,
    IReadOnlyCollection<BatchItemResult> Results);

internal sealed record BatchItemResult(
    string Id,
    string Operation,
    string Status,
    int? DelayMs,
    string? Error);

internal static class BatchItemStatus
{
    public const string Succeeded = "Succeeded";
    public const string Failed = "Failed";
}

internal sealed class BatchProcessingOptions
{
    public int MaxParallelism { get; init; } = 10;
}

internal sealed class Layer2Client(HttpClient httpClient)
{
    public async Task<Layer2SimulationResponse> SimulateAsync(string operation, CancellationToken cancellationToken)
    {
        using var scope = Tracer.Instance.StartActive("layer2.simulate");
        scope.Span.Type = SpanTypes.Http;
        scope.Span.ResourceName = "POST /api/simulate";
        scope.Span.SetTag("layer2.operation", operation);

        using var response = await httpClient.PostAsJsonAsync("/api/simulate", new Layer2SimulationRequest(operation), cancellationToken);

        if (response.IsSuccessStatusCode)
        {
            var payload = await response.Content.ReadFromJsonAsync<Layer2SimulationResponse>(cancellationToken: cancellationToken);
            if (payload is null)
            {
                throw new HttpRequestException("Layer2 returned an empty response.");
            }

            return payload;
        }

        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (response.StatusCode == System.Net.HttpStatusCode.BadRequest)
        {
            throw new Layer2ValidationException(body);
        }

        throw new HttpRequestException($"Layer2 returned {(int)response.StatusCode}: {body}");
    }
}

internal sealed class Layer2ValidationException(string message) : Exception(message);

internal sealed record Layer2SimulationRequest(string Operation);

internal sealed record Layer2SimulationResponse(
    string Operation,
    int DelayMs,
    DateTime StartedAtUtc,
    DateTime CompletedAtUtc);
