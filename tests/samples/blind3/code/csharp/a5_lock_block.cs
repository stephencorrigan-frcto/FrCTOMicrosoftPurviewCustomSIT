lock (_sync)
{
    _cache[key] = value;
    _hits++;
}