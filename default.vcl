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
    std.log("pre cookie " + req.http.Cookie);

    if (req.method == "PURGE") {
        ban("obj.http.Edge-Cache-Tag ~ " + req.http.CACHE_TAG);
        return (synth(200, "Cache successfully purged"));
    }
    cookie.parse(req.http.Cookie);

    if(cookie.isset("PROPLOGIN")){
        return (pass);
    }

    if (cookie.isset("GOOGLE_SEARCH_ID")) {


        if(cookie.isset("99_ab") && cookie.isset("GOOGLE_SEARCH_ID") && cookie.isset("_sess_id")){}
        else{
            std.log("executing set partial cookie");
            client.init("get_visitor_id", "http://sanity10.infoedge.com/api-aggregator/content/get-visitor-id");
            client.send("get_visitor_id");
            var.set("local_cookie",client.header("get_visitor_id","Set-Cookie", sep="`"));

            if(!cookie.isset("99_ab")){
                cookie.set("99_ab",regsub( var.get("local_cookie"),"(?:(?:^|.*;\s*)99_ab\s*\=\s*([^;]*).*$)|^.*$", "\1"));
            }
            if(!cookie.isset("GOOGLE_SEARCH_ID")){
                cookie.set("GOOGLE_SEARCH_ID",regsub( var.get("local_cookie"),"(?:(?:^|.*;\s*)GOOGLE_SEARCH_ID\s*\=\s*([^;]*).*$)|^.*$", "\1"));
            }
            if(!cookie.isset("_sess_id")){
                cookie.set("_sess_id",regsub( var.get("local_cookie"),"(?:(?:^|.*;\s*)_sess_id\s*\=\s*([^;]*).*$)|^.*$", "\1"));
                std.log("sess_id expired");
            }
        }
        #set req.http.X-cookie-data = req.http.Cookie;
        #set req.http.X-cookie-99ab = regsub( req.http.X-cookie-data , "(?:(?:^|.*;\s*)99_ab\s*\=\s*([^;]*).*$)|^.*$", "\1");
        # var.global_set("99ab-str",req.http.X-cookie-99ab);
        var.set_int("99ab-int",std.integer(cookie.get("99_ab")));
        std.log("executing has cookie block " + req.http.Cookie);
        var.global_set("new_user","false");
        var.global_set("99ab-str",cookie.get("99_ab"));
    }
    else{
        client.init("get_visitor_id", "http://sanity10.infoedge.com/api-aggregator/content/get-visitor-id");
        client.send("get_visitor_id");
        set req.http.X-cookie-data = client.header("get_visitor_id","Set-Cookie", sep="`");
        # var.global_set("99ab-str",req.http.X-cookie-99ab);
        var.global_set("new_user","true");
        set req.http.X-cookie-99ab = regsub( req.http.X-cookie-data , "(?:(?:^|.*;\s*)99_ab\s*\=\s*([^;]*).*$)|^.*$", "\1");

        # write a check if it's not an int
        var.set_int("99ab-int",std.integer(req.http.X-cookie-99ab));

        # comment this unneccesary
        var.global_set("99ab-str",req.http.X-cookie-99ab);
        std.log("double cookie data" + client.header("get_visitor_id","Set-Cookie", sep="`"));

        set req.http.Cookie = "99_ab=" + req.http.X-cookie-99ab + "; " ;
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
        std.log("X-cookie-99ab val is -1" + req.http.X-cookie-99ab);
    }
    #var.global_set("99ab-str",req.http.X-cookie-99ab);

    if (req.url ~ "xid" || req.url ~ "spid"){
        # std.log("returning hash");
	    return (hash);
    }

}

sub vcl_hash {

    if(req.http.X-UA-Device == "pc" || req.http.X-UA-Device == "bot"){
        hash_data("desktop");
    }
    elsif((req.http.X-UA-Device ~ "mobile" || req.http.X-UA-Device ~ "tablet")){
        hash_data("mobile");
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
    if(bereq.url ~ "xid" || bereq.url ~ "spid" && beresp.status >= 199 && beresp.status < 300){
        unset beresp.http.Cache-Control;
        set beresp.http.Cache-Control = "public";
	    set beresp.ttl = 10m;
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
    }

    std.log("new user status " + var.global_get("new_user"));
    if ( (req.url ~ "npxid" || req.url ~ "spid") && var.global_get("new_user") == "true"){

        if(resp.http.X-Cache == "HIT"){
            set req.http.cookie-data = client.header("get_visitor_id","Set-Cookie", sep="`");
            cookie.parse(req.http.cookie-data);
            var.set("sess_id", "_sess_id=" + cookie.get("_sess_id") + "; Max-Age=2; ");
            var.set("search_id", "GOOGLE_SEARCH_ID=" + cookie.get("GOOGLE_SEARCH_ID") + "; Max-Age=630720000; ");
            var.set("99_ab_val", "99_ab=" + var.global_get("99ab-str") + "; Max-Age=630720000; ");

            std.log("local cookie-data " + req.http.cookie-data);

            header.remove(resp.http.Set-Cookie, "GOOGLE_SEARCH_ID");
            header.remove(resp.http.Set-Cookie, "_sess_id");
            header.remove(resp.http.Set-Cookie, "99_ab");
            header.append(resp.http.Set-Cookie,str.split(req.http.cookie-data,1,"`"));
            header.append(resp.http.Set-Cookie,str.split(req.http.cookie-data,2,"`"));
            header.append(resp.http.Set-Cookie,str.split(req.http.cookie-data,3,"`"));
            set resp.http.X-request-ID = client.header("get_visitor_id","X-request-ID");
            set resp.http.x-visitor-id = client.header("get_visitor_id","x-visitor-id");
        }
        else{
            std.log("MISS cookie: " + resp.http.Cookie);
            #header.append(resp.http.Set-Cookie, str.split(client.header("get_visitor_id","Set-Cookie", sep="`"),1,"`"));
            header.append(resp.http.Set-Cookie,"99_ab=" + var.global_get("99ab-str") + "; Path=/; Domain=99acres.com; Max-Age=630720000; " );
        }
    }
}
