struct node { int val; struct node *next; };
struct node *push(struct node *head, int v) {
    struct node *n = malloc(sizeof *n);
    n->val = v; n->next = head;
    return n;
}