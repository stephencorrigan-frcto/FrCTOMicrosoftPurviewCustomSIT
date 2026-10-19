handler := http.HandlerFunc(s.serveHealth)
mux.Handle("/health", handler)