app.MapPost("/orders", async (OrderRequest req, IOrderService svc) =>
{
    var id = await svc.CreateAsync(req);
    return Results.Created($"/orders/{id}", id);
});