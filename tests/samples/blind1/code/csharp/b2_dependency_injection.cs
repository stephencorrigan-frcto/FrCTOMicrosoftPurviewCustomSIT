builder.Services.AddScoped<IPriceService, PriceService>();
var app = builder.Build();
app.MapGet("/health", () => Results.Ok());
app.Run();