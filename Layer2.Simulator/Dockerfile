FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY ["Layer2.Simulator/Layer2.Simulator.csproj", "Layer2.Simulator/"]
RUN dotnet restore "Layer2.Simulator/Layer2.Simulator.csproj"

COPY . .
WORKDIR "/src/Layer2.Simulator"
RUN dotnet publish "Layer2.Simulator.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
COPY --from=datadog/serverless-init:1 /datadog-init /app/datadog-init

RUN set -eux; \
	for attempt in 1 2 3 4 5; do \
		if apt-get update && apt-get install -y --no-install-recommends --fix-missing curl ca-certificates gnupg; then \
			break; \
		fi; \
		echo "Base apt install failed on attempt ${attempt}, retrying..."; \
		if [ "${attempt}" -eq 5 ]; then \
			echo "Base apt install failed after retries"; \
			exit 1; \
		fi; \
		sleep $((attempt * 5)); \
	done; \
	install -m 0755 -d /etc/apt/keyrings; \
	curl -fsSL https://keys.datadoghq.com/DATADOG_APT_KEY_CURRENT.public | gpg --dearmor -o /etc/apt/keyrings/datadog.gpg; \
	chmod a+r /etc/apt/keyrings/datadog.gpg; \
	echo "deb [signed-by=/etc/apt/keyrings/datadog.gpg] https://apt.datadoghq.com/ stable 7" > /etc/apt/sources.list.d/datadog.list; \
	for attempt in 1 2 3 4 5; do \
		if apt-get update && apt-get install -y --no-install-recommends --fix-missing datadog-apm-library-dotnet; then \
			break; \
		fi; \
		echo "Datadog apt install failed on attempt ${attempt}, retrying..."; \
		if [ "${attempt}" -eq 5 ]; then \
			echo "Datadog apt install failed after retries"; \
			exit 1; \
		fi; \
		sleep $((attempt * 5)); \
	done; \
	rm -rf /var/lib/apt/lists/*

ENV ASPNETCORE_URLS=http://+:8080
ENV CORECLR_ENABLE_PROFILING=1
ENV CORECLR_PROFILER={846F5F1C-F9AE-4B07-969E-05C26BC060D8}
ENV CORECLR_PROFILER_PATH=/opt/datadog/Datadog.Trace.ClrProfiler.Native.so
ENV DD_DOTNET_TRACER_HOME=/opt/datadog
ENV DD_INTEGRATIONS=/opt/datadog/integrations.json
ENV DD_PROFILING_ENABLED=1
ENV DD_SERVICE=layer2-simulator
ENV DD_ENV=local
ENV DD_VERSION=1.0.0
ENV DD_LOGS_ENABLED=true
ENV DD_LOGS_INJECTION=true
ENV DD_SOURCE=csharp
EXPOSE 8080

ENTRYPOINT ["/app/datadog-init"]
CMD ["dotnet", "Layer2.Simulator.dll"]
