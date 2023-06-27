vcl 4.1;
import std;
import reqwest;
import cookie;
import var;
import header;
import str;
import xkey;
import directors;
include "devicedetect.vcl";
include "backends.vcl";

sub vcl_recv {
    set req.backend_hint = vdir.backend();
    if (req.method == "PURGE" || req.method == "PUT") {
        if(req.url ~ "xkey"){
            var.set("purge-count",xkey.purge(req.http.CACHE_TAG));
            return (synth(200, "Purged Count: " + var.get("purge-count")));
        }
        if(req.http.delete-cache == "true"){
            return (purge);
        }
    }
    if (req.url ~ "health-check"){
        return (synth(200,"OK"));
    }
    call page_properties;
    if(var.get("page_identifier") == "uncacheable"){
        return (pass);
    }

    std.log("pre cookie " + req.http.Cookie);
    cookie.parse(req.http.Cookie);
    if(cookie.isset("PROPLOGIN")){
        return (pass);
    }
    if(var.get("is_segmentation") == "Y"){
        call set_segmentation;
    }

    if(var.get("page_identifier") ~ "srp"){
        if((req.http.nn-cache-agent == "nnacresbot-desktop" || req.http.nn-cache-agent == "nnacresbot-mobile" || cookie.get("GOOGLE_SEARCH_ID") == "1111111111111111111")){
            return (hash);
        }
        if( var.get("isBot") == "Y" ){
            return (hash);
        }
    }
    elsif (var.get("page_identifier") == "npxid" || var.get("page_identifier") == "spid"){
            return (hash);
    }
    set req.http.varnish-is-caching = "N";
    return (pass);
}

sub vcl_hash {
    call devicedetect;
    set req.http.varnish-is-caching = "Y";
    if(req.http.X-UA-Device ~ "mobile" || req.http.X-UA-Device ~ "tablet" || req.http.nn-cache-agent == "nnacresbot-mobile" || std.tolower(req.http.User-Agent) ~ "mobile"){
        hash_data("mobile");
    }
    elsif(req.http.X-UA-Device == "pc" || req.http.X-UA-Device == "bot" || req.http.nn-cache-agent == "nnacresbot-desktop"){
        hash_data("desktop");
    }
    if(var.get("is_segmentation") == "Y"){
        hash_data("99_ab=" + var.get("99ab-code"));
    }
    else{
        hash_data("99_ab=A");
    }
    hash_data(req.url);
    return (lookup);
}
sub vcl_hit {
    if(!cookie.isset("99_ab") || !cookie.isset("GOOGLE_SEARCH_ID") || !cookie.isset("_sess_id") || !req.http.X-request-ID){
        set req.http.x-api-time = std.timed_call(set_cookie);
    }
}
sub vcl_backend_response {
    if(bereq.http.varnish-is-caching != "N" && beresp.status > 199 && beresp.status < 300){
        if(beresp.http.nn-cache-control){
            if(beresp.http.nn-cache-control == "no-store"){
                set beresp.uncacheable = true;
            }
            else{
                set beresp.http.Cache-Control = "public";
                set beresp.http.xkey = beresp.http.Edge-Cache-Tag;
                set beresp.ttl = std.duration(str.split(str.split(beresp.http.nn-cache-control,1,",") , 2,"="),0s);
                if (bereq.url ~ "^(?!.*projects).*-ffid.*|.*-nrffid.*|.*-rnpffid.*|.*-npffid.*|.*-cffid.*|.*-crffid.*|.*-xffid.*"){
                    set beresp.ttl = 24h;
                    unset beresp.http.xkey;
                }
                set beresp.grace = 0s;
            }
        }
        else{
            set beresp.uncacheable = true;
        }
        if(bereq.http.do-esi == "true"){
            set beresp.do_esi = true;
        }
    }

    return(deliver);
}

# ["_sess_id","GOOGLE_SEARCH_ID","99_ab"]

sub vcl_deliver {

    if (obj.hits > 0) {
        set resp.http.X-Cache-Status = "HIT";
    } else {
        set resp.http.X-Cache-Status = "MISS";
    }
    if(resp.http.X-Cache-Status == "HIT"){
        header.remove(resp.http.Set-Cookie, "99_ab");
        header.remove(resp.http.Set-Cookie, "_sess_id");
        header.remove(resp.http.Set-Cookie, "GOOGLE_SEARCH_ID");
        unset resp.http.x-visitor-id;
        unset resp.http.X-request-ID;
        unset resp.http.nn-cache-ttl;
        unset resp.http.authorizationtoken;
        header.remove(resp.http.Set-Cookie,"vary");
        set resp.http.x-cache-age = resp.http.Age;
        if(std.tolower(req.http.user-agent) ~ "lighthouse"){
            header.append(resp.http.Set-Cookie,"ilh=Y");
        }
    }

    if ( var.get("page_identifier") != "uncacheable" && resp.http.X-Cache-Status == "HIT"){
        if(!cookie.isset("99_ab")){
            header.append(resp.http.Set-Cookie,var.get("99_ab"));
        }
        if(!cookie.isset("GOOGLE_SEARCH_ID")){
            header.append(resp.http.Set-Cookie,var.get("GOOGLE_SEARCH_ID"));
            if(!req.http.x-visitor_id){
                set resp.http.x-visitor-id = regsub(var.get("GOOGLE_SEARCH_ID"),"(?:(?:^|.*;\s*)GOOGLE_SEARCH_ID\s*\=\s*([^;]*).*$)|^.*$", "\1");  // correction done
            }
        }
        if(!cookie.isset("_sess_id")){
            header.append(resp.http.Set-Cookie,var.get("_sess_id"));
        }
        if(!req.http.X-request-ID){
            set resp.http.X-request-ID = client.header("get_visitor_id","X-request-ID");
        }
        if(cookie.isset("GOOGLE_SEARCH_ID") && !req.http.x-visitor-id){
            set resp.http.x-visitor-id = cookie.get("GOOGLE_SEARCH_ID");
        }
//        if(!cookie.isset("auth_token")){
//            header.append(resp.http.Set-Cookie,client.header("get_visitor_id","Authorizationtoken"));
//        }
    }
    unset resp.http.xkey;
}

sub page_properties{
    if( (req.http.User-Agent ~ "AdsBot-Google" || req.http.User-Agent ~ "Googlebot")){
        var.set("isBot","Y");
    }
    if(req.url ~ "-npxid-"){
        var.set("page_identifier","npxid");
        set req.http.do-esi=true;
    }
    if(req.url ~ "-spid-"){
        var.set("page_identifier","spid");
        set req.http.do-esi=true;
        var.set("is_segmentation","N");
    }
    elsif(req.url ~ "^(?!.*projects).*-ffid.*|.*-nrffid.*|.*-rnpffid.*|.*-npffid.*|.*-cffid.*|.*-crffid.*|.*-xffid.*"){
        var.set("page_identifier","srp");
        var.set("is_segmentation","N");

    }
    else{
        var.set("page_identifier","uncacheable");
        set req.http.varnish-is-caching = "N";
        set req.http.do-esi=false;
        var.set("is_segmentation","N");
    }
}

sub set_segmentation {
    if(var.get("isBot") == "Y"){
        var.set("99ab-code","A");
    }
    else{
        if(cookie.isset("99_ab")){
            var.set_int("99ab-int",std.integer(cookie.get("99_ab"),101));
        }
        else{
            var.set("99ab-str",var.get("99_ab"));
            std.log("99ab-str val is" + var.get("99ab-str"));
            var.set_int("99ab-int",std.integer(regsub( var.get("99ab-str"),"(?:(?:^|.*;\s*)99_ab\s*\=\s*([^;]*).*$)|^.*$", "\1"),101));
        }
        if( var.get_int("99ab-int") != 101){
            if(var.get("page_identifier") == "srp"){
                if(var.get_int("99ab-int") > 50 && var.get_int("99ab-int") < 56){
                    var.set("99ab-code", "A");
                }
                else{
                    var.set("99ab-code", "B");
                }
            }
        }
        else{
            std.log("X-cookie-99ab val is -1" + var.get("99ab-int"));
            return (synth(502,"Invalid 99AB Code"));
        }
    }
}

sub set_cookie {
    client.init("get_visitor_id", var.global_get("api-url"));
    client.set_header("get_visitor_id","User-Agent","Varnish");
    client.set_header("get_visitor_id","Cookie",cookie.get_string());
    client.send("get_visitor_id");
    if(client.status("get_visitor_id") < 200 || client.status("get_visitor_id") > 210){
        return (synth(502,"get-visitor-api returned null"));
    }

    set req.http.cookie-data = client.header("get_visitor_id","Set-Cookie", sep="`");
    std.log("api call cookie data " + client.header("get_visitor_id","Set-Cookie", sep="`"));

    var.set("first" , str.split(req.http.cookie-data,1,"`"));
    var.set("second" , str.split(req.http.cookie-data,2,"`"));
    var.set("third" , str.split(req.http.cookie-data,3,"`"));
    if(req.http.Cookie != ""){
        set req.http.Cookie = req.http.Cookie + "; ";
    }
    if(!cookie.isset("_sess_id")){
        if(var.get("first") ~ "_sess_id"){
            var.set("_sess_id",var.get("first"));
            set req.http.Cookie = req.http.Cookie + var.get("first") + "; ";
        }
        elsif(var.get("second") ~ "_sess_id"){
            var.set("_sess_id",var.get("second"));
            set req.http.Cookie = req.http.Cookie + var.get("second") + "; ";
        }
        else{
            var.set("_sess_id",var.get("third"));
            set req.http.Cookie = req.http.Cookie + var.get("third") + "; ";
        }
    }
   if(!cookie.isset("GOOGLE_SEARCH_ID")){
        if(var.get("first") ~ "GOOGLE_SEARCH_ID"){
            var.set("GOOGLE_SEARCH_ID",var.get("first"));
            set req.http.Cookie = req.http.Cookie + var.get("first") + "; ";
        }
        elsif(var.get("second") ~ "GOOGLE_SEARCH_ID"){
            var.set("GOOGLE_SEARCH_ID",var.get("second"));
            set req.http.Cookie = req.http.Cookie + var.get("second") + "; ";
        }
        else{
            var.set("GOOGLE_SEARCH_ID",var.get("third"));
            set req.http.Cookie = req.http.Cookie + var.get("third") + "; ";
        }
    }
   if(!cookie.isset("99_ab")){
        if(var.get("first") ~ "99_ab"){
            var.set("99_ab",var.get("first"));
            set req.http.Cookie = req.http.Cookie + var.get("first") + "; ";
        }
        elsif(var.get("second") ~ "99_ab"){
            var.set("99_ab",var.get("second"));
            set req.http.Cookie = req.http.Cookie + var.get("second") + "; ";
        }
        else{
            var.set("99_ab",var.get("third"));
            set req.http.Cookie = req.http.Cookie + var.get("third") + "; ";
        }
    }
}
