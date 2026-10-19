type Server struct {
	*http.Server
	log *slog.Logger
}