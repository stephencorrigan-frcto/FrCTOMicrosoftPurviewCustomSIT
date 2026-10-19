if err := db.Ping(); err != nil {
	log.Fatalf("db unavailable: %v", err)
}