char *p = buf;
while (*p != '\0') {
    if (*p == ',') *p = ';';
    p++;
}