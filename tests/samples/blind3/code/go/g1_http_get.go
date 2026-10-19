resp, err := http.Get(url)
if err != nil {
	return err
}
defer resp.Body.Close()