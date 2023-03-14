vcl 4.1;
import std;
import reqwest;
import cookie;
import var;
import header;

backend default {
    .host = "172.16.3.50";
    .port = "31200";
}

sub vcl_init {
    new client = reqwest.client();
}

sub vcl_recv {

    std.log("pre cookie " + req.http.Cookie);


    # if(req.http.Cookie ~ "^;99_ab=([0-9]+);$"){
        # std.log("new user detected");
        # unset req.http.Cookie;
    # }

    set req.http.Cache-Control = "public";

    if (req.method == "PURGE") {
        ban("obj.http.x-key == " + req.http.x-key);
        return (synth(200, "Cache successfully purged"));
    }

    if (req.http.Cookie) {
        set req.http.X-cookie-data = req.http.Cookie;
        set req.http.X-cookie-99ab = regsub( req.http.X-cookie-data , "(?:(?:^|.*;\s*)99_ab\s*\=\s*([^;]*).*$)|^.*$", "\1");
        # var.global_set("99ab-str",req.http.X-cookie-99ab);
        var.set_int("99ab-int",std.integer(req.http.X-cookie-99ab));
        std.log("executing has cookie block " + req.http.Cookie);
        var.global_set("new_user","false");
    }
    else{
        client.init("get_visitor_id", "http://sanity10.infoedge.com/api-aggregator/content/get-visitor-id");
        client.send("get_visitor_id");
        set req.http.X-cookie-data = client.header("get_visitor_id","Set-Cookie", sep="; "); 
        # var.global_set("99ab-str",req.http.X-cookie-99ab);        
        var.global_set("new_user","true");
        set req.http.X-cookie-99ab = regsub( req.http.X-cookie-data , "(?:(?:^|.*;\s*)99_ab\s*\=\s*([^;]*).*$)|^.*$", "\1");
        
        # write a check if it's not an int
        var.set_int("99ab-int",std.integer(req.http.X-cookie-99ab));
        
        # comment this unneccesary
        var.global_set("99ab-str",req.http.X-cookie-99ab);

        std.log("double cookie data" + client.header("get_visitor_id","Set-Cookie", sep="; "));
    }
    
    if( var.get_int("99ab-int") >-1){
        if(var.get_int("99ab-int") > -1 && var.get_int("99ab-int") < 50){            
            var.global_set("99ab-code", "A");
        }
        else{            
            var.global_set("99ab-code", "B");

        }
        # std.log("X-cookie-99ab val is " + req.http.X-cookie-99ab);

    }
    else{
        std.log("X-cookie-99ab val is -1" + req.http.X-cookie-99ab);
    }
    var.global_set("99ab-str",req.http.X-cookie-99ab);



    if (req.url ~ "xid" || req.url ~ "spid"){
        # std.log("returning hash");
	    return (hash);
    }

}

sub vcl_hash {

    # hash_data("99ab=" + req.http.X-cookie-99ab);

    std.log(" 99ab:val hash " + req.http.X-cookie-99ab);

    hash_data("99_ab=" + var.global_get("99ab-code"));

    # unset req.http.Cookie;
    # unset req.http.X-cookie-data;
    # unset req.http.X-cookie-99ab;

    # set req.http.Cookie = "99_ab=" + var.global_get("99ab-str");
    set req.http.Cookie = "99_ab=" + var.global_get("99ab-str");

    # unset req.http.X-cookie-99ab;

    std.log("final cookie data" + req.http.Cookie);

    hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }

    return (lookup);
}


sub vcl_backend_response {

	
    set beresp.ttl = 0s;
    if(bereq.url ~ "xid" || bereq.url ~ "spid"){
        unset beresp.http.Cache-Control;
        set beresp.http.Cache-Control = "public";
	    set beresp.ttl = 10m;
        set beresp.http.x-key = "xid";
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

    
    if ( (req.url ~ "xid" || req.url ~ "spid") && var.global_get("new_user") == "true"){

        if(resp.http.X-Cache == "HIT"){
            set req.http.cookie-data = client.header("get_visitor_id","Set-Cookie", sep="; ");
            cookie.parse(req.http.cookie-data);

            var.set("sess_id", "_sess_id=" + cookie.get("_sess_id"));
            var.set("search_id", "GOOGLE_SEARCH_ID=" + cookie.get("GOOGLE_SEARCH_ID"));
            var.set("99_ab_val", "99_ab=" + var.global_get("99ab-str"));

            std.log("local var set " + var.get("search_id"));
            std.log("local var set " + var.get("sess_id"));

            header.remove(resp.http.Set-Cookie, "GOOGLE_SEARCH_ID");
            header.remove(resp.http.Set-Cookie, "_sess_id");
            header.remove(resp.http.Set-Cookie, "99_ab");
            header.append(resp.http.Set-Cookie,var.get("sess_id"));            
            header.append(resp.http.Set-Cookie,var.get("search_id"));
            header.append(resp.http.Set-Cookie,var.get("99_ab_val"));
            # header.append(resp.http.Set-Cookie,"why-this-kolaveri-di");
            # set resp.http.Set-Cookie = "nothing=working;";
            std.log("cookie after hit " + resp.http.Set-Cookie);
        }
        else{

            std.log("MISS cookie: " + resp.http.Cookie);
            header.append(resp.http.Set-Cookie, "99_ab=" + var.global_get("99ab-str"));
            std.log( "fial x cookie data=" + req.http.Cookie);
        }
    }
    std.log("req hash is " + req.hash);


    set resp.http.x-test = "From Varnish";
}

