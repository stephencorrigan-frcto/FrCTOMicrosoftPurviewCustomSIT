using System;
using System.Collections.Generic;

namespace CorpActionCapture
{
    public class PositionLoader
    {
        private readonly string _connectionString;

        public PositionLoader(string connectionString)
        {
            _connectionString = connectionString;
        }

        public List<string> LoadSymbols(int limit)
        {
            var symbols = new List<string>();
            for (int i = 0; i < limit; i++)
            {
                if (i % 2 == 0)
                {
                    symbols.Add("SYM" + i);
                }
            }
            return symbols;
        }
    }
}