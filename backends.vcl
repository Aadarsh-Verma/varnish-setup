backend default {
    .host = "10.10.83.27";
    .port = "80";
}

sub vcl_init {
    new client = reqwest.client();
    var.global_set("api-url","http://99services.99.jsb9.net/content-generic-service/get-visitor-id");
}