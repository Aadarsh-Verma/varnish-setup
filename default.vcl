vcl 4.1;
import std;
import reqwest;
import cookie;
import var;
import header;
import str;
include "devicedetect.vcl";

backend default {
    .host = "172.16.3.50";
    .port = "31200";
}
sub vcl_init {
    new client = reqwest.client();
}

sub vcl_recv {
    call devicedetect;
    call page_properties;
    std.log("pre cookie " + req.http.Cookie);

    if (req.method == "PURGE") {
        ban("obj.http.Edge-Cache-Tag ~ " + req.http.CACHE_TAG);
        return (synth(200, "Cache successfully purged"));
    }
    cookie.parse(req.http.Cookie);

    if(cookie.isset("PROPLOGIN")){
        return (pass);
    }

    if(!cookie.isset("99_ab") || !cookie.isset("GOOGLE_SEARCH_ID") || !cookie.isset("_sess_id") || !req.http.X-request-ID){

        std.log("executing set partial cookie");
        call set_cookie;
        std.log("after set cookie " + req.http.Cookie);
        if(cookie.isset("99_ab")){
            var.set_int("99ab-int",std.integer(cookie.get("99_ab")));
        }
        else{
            var.set("99ab-str",var.global_get("99_ab"));
            std.log("99ab-str val is" + var.get("99ab-str"));
            var.set_int("99ab-int",std.integer(regsub( var.get("99ab-str"),"(?:(?:^|.*;\s*)99_ab\s*\=\s*([^;]*).*$)|^.*$", "\1")));
        }
    }
    else{
        var.set("99ab-str",var.global_get("99_ab"));
        std.log("99ab-str val is" + var.get("99ab-str"));
        var.set_int("99ab-int",std.integer(cookie.get("99_ab")));
    }
    if( var.get_int("99ab-int") >-1){
        if(var.get_int("99ab-int") > -1 && var.get_int("99ab-int") < 50){
            var.global_set("99ab-code", "A");
        }
        else{
            var.global_set("99ab-code", "B");
        }
    }
    else{
        std.log("X-cookie-99ab val is -1" + var.get("99ab-int"));
    }

    if(var.global_get("page_identifier") ~ "srp"){
        if((req.http.nn-cache-agent == "nnacresbot-desktop" || req.http.nn-cache-agent == "nnacresbot-mobile" || cookie.get("GOOGLE_SEARCH_ID") == "1111111111111111111")){
            return (hash);
        }
        if(req.http.User-Agent ~ "AdsBot-Google" || req.http.User-Agent ~ "Googlebot"){
            return (hash);
        }
    }
    elsif (req.url ~ "xid" || req.url ~ "spid"){
	    return (hash);
    }

}

sub vcl_hash {

    if(req.http.X-UA-Device ~ "mobile" || req.http.X-UA-Device ~ "tablet" || req.http.nn-cache-agent == "nnacresbot-mobile"){
        hash_data("mobile");
    }
    elsif(req.http.X-UA-Device == "pc" || req.http.X-UA-Device == "bot" || req.http.nn-cache-agent == "nnacresbot-desktop"){
        hash_data("desktop");
    }
    hash_data("99_ab=" + var.global_get("99ab-code"));

    hash_data(req.url);

    # if (req.http.host) {
    #     hash_data(req.http.host);
    # } else {
    #     hash_data(server.ip);
    # }

    return (lookup);
}

sub vcl_backend_response {

    set beresp.ttl = 0s;

    if(var.global_get("page_identifier") != "uncacheable" && beresp.status > 199 && beresp.status < 300){
        unset beresp.http.Cache-Control;
        set beresp.http.Cache-Control = "public";
        if(beresp.http.Edge-Control){
            if(beresp.http.Edge-Control == "no-store"){
                set beresp.uncacheable = true;
                set beresp.ttl = 0s;
            }
            else{
                set beresp.ttl = std.duration(str.split(str.split(beresp.http.Edge-Control,1,",") , 2,"="),10m);
            }
        }
        else{
            set beresp.ttl = 10m;
        }
        if(var.global_get("do_esi") == "y"){
            set beresp.do_esi = true;
        }
    }

    return(deliver);
}

# ["_sess_id","GOOGLE_SEARCH_ID","99_ab"]

sub vcl_deliver {

    if (obj.hits > 0) {
    	set resp.http.X-Cache = "HIT";
    } else {
    	set resp.http.X-Cache = "MISS";
    }

    if(resp.http.X-Cache == "HIT"){
        header.remove(resp.http.Set-Cookie, "99_ab");
        header.remove(resp.http.Set-Cookie, "_sess_id");
        header.remove(resp.http.Set-Cookie, "GOOGLE_SEARCH_ID");
        header.remove(resp.http.authorizationtoken,"authorizationtoken");
        header.remove(resp.http.x-visitor-id,"x-visitor-id");
        header.remove(resp.http.Set-Cookie,"vary");
    }

    if ( var.global_get("page_identifier") != "uncacheable"){
        if(!cookie.isset("99_ab")){
            header.append(resp.http.Set-Cookie,var.global_get("99_ab"));
        }
        if(!cookie.isset("GOOGLE_SEARCH_ID")){
            header.append(resp.http.Set-Cookie,var.global_get("GOOGLE_SEARCH_ID"));
            if(!req.http.x-visitor_id){
                set resp.http.x-visitor-id = var.global_get("GOOGLE_SEARCH_ID");
            }
        }
        if(!cookie.isset("_sess_id")){
            header.append(resp.http.Set-Cookie,var.global_get("_sess_id"));
        }
        if(!req.http.X-request-ID){
            set resp.http.X-request-ID = client.header("get_visitor_id","X-request-ID");
        }
    }

}

sub page_properties{
    if(req.url ~ "npxid"){
        var.global_set("page_identifier","npxid");
        var.global_set("do_esi","y");
    }
    elsif(req.url ~ "spid"){
        var.global_set("page_identifier","spid");
        var.global_set("do_esi","y");
    }
    elsif(req.url ~ "^(?!.*projects).*-ffid.*|.*-nrffid.*|.*-rnpffid.*|.*-npffid.*|.*-cffid.*|.*-crffid.*|.*-xffid.*"){
        var.global_set("page_identifier","srp");
    }
    else{
        var.global_set("page_identifier","uncacheable");
        var.global_set("do_esi","n");
    }
}


sub set_cookie {
    client.init("get_visitor_id", "http://sanity9.infoedge.com/api-aggregator/content/get-visitor-id");
    client.set_header("get_visitor_id","User-Agent","Varnish");
    client.send("get_visitor_id");
    set req.http.cookie-data = client.header("get_visitor_id","Set-Cookie", sep="`");
    std.log("set_cookie initiated" + client.header("get_visitor_id","Set-Cookie", sep="`"));

    var.set("first" , str.split(req.http.cookie-data,1,"`"));
    var.set("second" , str.split(req.http.cookie-data,2,"`"));
    var.set("third" , str.split(req.http.cookie-data,3,"`"));
    # std.log("first is " + var.get("first"));
    if(!cookie.isset("_sess_id")){
        if(var.get("first") ~ "_sess_id"){
            var.global_set("_sess_id",var.get("first"));
            set req.http.Cookie = req.http.Cookie + var.get("first") + "; ";
        }
        elsif(var.get("second") ~ "_sess_id"){
            var.global_set("_sess_id",var.get("second"));
            set req.http.Cookie = req.http.Cookie + var.get("second") + "; ";
        }
        else{
            var.global_set("_sess_id",var.get("third"));
            set req.http.Cookie = req.http.Cookie + var.get("third") + "; ";
        }
    }
   if(!cookie.isset("GOOGLE_SEARCH_ID")){
        if(var.get("first") ~ "GOOGLE_SEARCH_ID"){
            var.global_set("GOOGLE_SEARCH_ID",var.get("first"));
            set req.http.Cookie = req.http.Cookie + var.get("first") + "; ";
        }
        elsif(var.get("second") ~ "GOOGLE_SEARCH_ID"){
            var.global_set("GOOGLE_SEARCH_ID",var.get("second"));
            set req.http.Cookie = req.http.Cookie + var.get("second") + "; ";
        }
        else{
            var.global_set("GOOGLE_SEARCH_ID",var.get("third"));
            set req.http.Cookie = req.http.Cookie + var.get("third") + "; ";
        }
    }
   if(!cookie.isset("99_ab")){
        if(var.get("first") ~ "99_ab"){
            var.global_set("99_ab",var.get("first"));
            set req.http.Cookie = req.http.Cookie + var.get("first") + "; ";
        }
        elsif(var.get("second") ~ "99_ab"){
            var.global_set("99_ab",var.get("second"));
            set req.http.Cookie = req.http.Cookie + var.get("second") + "; ";
        }
        else{
            var.global_set("99_ab",var.get("third"));
            set req.http.Cookie = req.http.Cookie + var.get("third") + "; ";
        }
    }
}
