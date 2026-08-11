FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY GroupRide.sln ./
COPY src/GroupRide.Domain/GroupRide.Domain.csproj src/GroupRide.Domain/
COPY src/GroupRide.Cohesion/GroupRide.Cohesion.csproj src/GroupRide.Cohesion/
COPY src/GroupRide.Infrastructure/GroupRide.Infrastructure.csproj src/GroupRide.Infrastructure/
COPY src/GroupRide.Api/GroupRide.Api.csproj src/GroupRide.Api/
RUN dotnet restore src/GroupRide.Api/GroupRide.Api.csproj
COPY src/ src/
RUN dotnet publish src/GroupRide.Api/GroupRide.Api.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://0.0.0.0:5080
EXPOSE 5080
ENTRYPOINT ["dotnet", "GroupRide.Api.dll"]
