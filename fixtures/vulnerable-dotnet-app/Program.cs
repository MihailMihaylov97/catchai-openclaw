using VulnerableApp.Services;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
builder.Services.AddScoped<ProjectService>();

var app = builder.Build();
app.MapControllers();
app.Run();
