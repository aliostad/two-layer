FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY ["Layer1.BatchApi/Layer1.BatchApi.csproj", "Layer1.BatchApi/"]
RUN dotnet restore "Layer1.BatchApi/Layer1.BatchApi.csproj"

COPY . .
WORKDIR "/src/Layer1.BatchApi"
RUN dotnet publish "Layer1.BatchApi.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "Layer1.BatchApi.dll"]
