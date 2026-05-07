using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.Configure<OperationDelayOptions>(builder.Configuration.GetSection("OperationDelays"));
builder.Services.AddSingleton<DelaySampler>();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

app.MapPost("/api/simulate", async (SimulationRequest request, DelaySampler sampler, CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.Operation))
    {
        return Results.BadRequest(new { message = "Operation is required." });
    }

    if (!sampler.TrySample(request.Operation, out var delayMs))
    {
        return Results.BadRequest(new
        {
            message = $"Unknown operation '{request.Operation}'.",
            availableOperations = sampler.GetOperations()
        });
    }

    var startedAtUtc = DateTime.UtcNow;
    await Task.Delay(delayMs, cancellationToken);
    var completedAtUtc = DateTime.UtcNow;

    return Results.Ok(new SimulationResponse(request.Operation, delayMs, startedAtUtc, completedAtUtc));
})
.WithName("SimulateOperationDelay");

app.MapGet("/api/operations", (DelaySampler sampler) => Results.Ok(sampler.GetOperations()))
    .WithName("GetSupportedOperations");

app.Run();

internal sealed record SimulationRequest(string Operation);

internal sealed record SimulationResponse(
    string Operation,
    int DelayMs,
    DateTime StartedAtUtc,
    DateTime CompletedAtUtc);

internal sealed record OperationDescriptor(string Operation, double MeanMs, double StandardDeviationMs);

internal sealed class OperationDelayOptions
{
    public Dictionary<string, DelayProfile> Operations { get; init; } = new(StringComparer.OrdinalIgnoreCase);
}

internal sealed class DelayProfile
{
    public double MeanMs { get; init; }
    public double StandardDeviationMs { get; init; }
}

internal sealed class DelaySampler
{
    private readonly IReadOnlyDictionary<string, DelayProfile> operations;

    public DelaySampler(IOptions<OperationDelayOptions> options)
    {
        if (options.Value.Operations.Count == 0)
        {
            throw new InvalidOperationException("At least one operation must be configured in OperationDelays:Operations.");
        }

        operations = new Dictionary<string, DelayProfile>(options.Value.Operations, StringComparer.OrdinalIgnoreCase);
    }

    public bool TrySample(string operation, out int delayMs)
    {
        if (!operations.TryGetValue(operation, out var profile))
        {
            delayMs = 0;
            return false;
        }

        delayMs = Math.Max(10, (int)Math.Round(NextGaussian(profile.MeanMs, profile.StandardDeviationMs)));
        return true;
    }

    public IReadOnlyCollection<OperationDescriptor> GetOperations() => operations
        .Select(pair => new OperationDescriptor(pair.Key, pair.Value.MeanMs, pair.Value.StandardDeviationMs))
        .OrderBy(item => item.Operation)
        .ToArray();

    private static double NextGaussian(double mean, double standardDeviation)
    {
        if (standardDeviation <= 0)
        {
            return mean;
        }

        var u1 = 1.0 - Random.Shared.NextDouble();
        var u2 = 1.0 - Random.Shared.NextDouble();
        var standardNormal = Math.Sqrt(-2.0 * Math.Log(u1)) * Math.Cos(2.0 * Math.PI * u2);
        return mean + standardDeviation * standardNormal;
    }
}
