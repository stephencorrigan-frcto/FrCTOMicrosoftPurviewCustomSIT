func (s *Server) Start(addr string) error {
	return http.ListenAndServe(addr, s.router)
}