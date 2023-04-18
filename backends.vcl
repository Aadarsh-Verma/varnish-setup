backend default {
    .host = "172.16.3.50";
    .port = "31200";
}

sub vcl_init {
    new client = reqwest.client();
    var.global_set("api-url","http://sanity10.infoedge.com/api-aggregator/content/get-visitor-id");
}