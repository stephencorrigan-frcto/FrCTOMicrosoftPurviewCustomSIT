public static class StringExtensions
{
    public static bool IsTicker(this string s) => s.Length <= 5 && s.All(char.IsUpper);
}