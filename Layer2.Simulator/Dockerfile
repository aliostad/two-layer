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

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "Layer2.Simulator.dll"]
