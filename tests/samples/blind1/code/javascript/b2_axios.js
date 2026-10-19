const { data } = await axios.get(`${BASE_URL}/prices`, { params: { symbol } });
setPrices(data.items);