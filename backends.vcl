backend default {
    .host = "172.16.3.50";
    .port = "31200";
}

sub vcl_init {
    new client = reqwest.client();
    new vdir = directors.round_robin();
    vdir.add_backend(default);
    var.global_set("api-url","http://sanity10.infoedge.com/api-aggregator/content/get-visitor-id");
}