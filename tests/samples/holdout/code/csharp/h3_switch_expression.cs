string Label(int score) => score switch
{
    > 90 => "high",
    > 50 => "medium",
    _ => "low"
};