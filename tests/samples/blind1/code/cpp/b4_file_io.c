FILE *fp = fopen("trades.csv", "r");
if (!fp) { perror("fopen"); return -1; }
fclose(fp);