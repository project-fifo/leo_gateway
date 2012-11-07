%%======================================================================
%%
%% Leo S3 HTTP
%%
%% Copyright (c) 2012 Rakuten, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% ---------------------------------------------------------------------
%% Leo S3 HTTP - powered by Cowboy version
%% @doc
%% @end
%%======================================================================
-module(leo_s3_http_cowboy).

-author('Yosuke Hara').
-author('Yoshiyuki Kanno').

-export([start/1, stop/0]).
-export([init/3, handle/2, terminate/2]).

-include("leo_gateway.hrl").
-include("leo_s3_http.hrl").

-include_lib("cowboy/include/http.hrl").
-include_lib("leo_commons/include/leo_commons.hrl").
-include_lib("leo_logger/include/leo_logger.hrl").
-include_lib("leo_object_storage/include/leo_object_storage.hrl").
-include_lib("leo_s3_libs/include/leo_s3_auth.hrl").
-include_lib("eunit/include/eunit.hrl").

-undef(SERVER_HEADER).
-define(SERVER_HEADER, {'Server',<<"LeoFS">>}).
-define(SSL_PROC_NAME, list_to_atom(lists:append([?MODULE_STRING, "_ssl"]))).

-record(cache_condition, {
          expire          = 0  :: integer(), %% specified per sec
          max_content_len = 0  :: integer(), %% No cache if Content-Length of a response header was &gt this
          content_types   = [] :: list(),    %% like ["image/png", "image/gif", "image/jpeg"]
          path_patterns   = [] :: list()     %% compiled regular expressions
         }).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
%% start web-server.
%%
-spec(start(#http_options{}) ->
             ok).
start(#http_options{port                   = Port,
                    ssl_port               = SSLPort,
                    ssl_certfile           = SSLCertFile,
                    ssl_keyfile            = SSLKeyFile,
                    num_of_acceptors       = NumOfAcceptors,
                    s3_api                 = UseS3API,
                    cache_plugin           = CachePlugIn,
                    cache_expire           = CacheExpire,
                    cache_max_content_len  = CacheMaxContentLen,
                    cachable_content_type  = CachableContentTypes,
                    cachable_path_pattern  = CachablePathPatterns,
                    acceptable_max_obj_len = AcceptableMaxObjLen,
                    chunked_obj_len        = ChunkedObjLen,
                    threshold_obj_len      = ThresholdObjLen}) ->
    InternalCache = (CachePlugIn == []),
    Dispatch      = [{'_', [{'_', ?MODULE,
                             [?env_layer_of_dirs(), InternalCache, UseS3API,
                              AcceptableMaxObjLen, ChunkedObjLen, ThresholdObjLen]}]}],

    Config = case InternalCache of
                 %% Using inner-cache
                 true ->
                     [{dispatch, Dispatch}];
                 %% Using cache-plugin
                 false ->
                     CacheCondition = #cache_condition{expire          = CacheExpire,
                                                       max_content_len = CacheMaxContentLen,
                                                       content_types   = CachableContentTypes,
                                                       path_patterns   = CachablePathPatterns},
                     [{dispatch,   Dispatch},
                      {onrequest,  onrequest(CacheCondition)},
                      {onresponse, onresponse(CacheCondition)}]
             end,

    application:start(ecache),
    cowboy:start_listener(?MODULE, NumOfAcceptors,
                          cowboy_tcp_transport, [{port, Port}],
                          cowboy_http_protocol, Config),
    cowboy:start_listener(?SSL_PROC_NAME, NumOfAcceptors,
                          cowboy_ssl_transport, [{port,     SSLPort},
                                                 {certfile, SSLCertFile},
                                                 {keyfile,  SSLKeyFile}],
                          cowboy_http_protocol, Config).


%% @doc
-spec(stop() ->
             ok).
stop() ->
    cowboy:stop_listener(?MODULE),
    cowboy:stop_listener(?SSL_PROC_NAME).


%% @doc Initializer
init({_Any, http}, Req, Opts) ->
    {ok, Req, Opts}.


%% @doc Handle a request
%% @callback
handle(Req, State) ->
    Key = gen_key(Req),
    handle(Req, State, Key).

handle(Req, [{NumOfMinLayers, NumOfMaxLayers}, HasInnerCache, UseS3API,
             AcceptableObjLen, ChunkedObjLen, ThresholdObjLen] = State, Path) ->
    {Prefix, IsDir, Path2, Req2} =
        case cowboy_http_req:qs_val(?HTTP_HEAD_BIN_PREFIX, Req) of
            {undefined, Req1} ->
                HasTermSlash = (?BIN_SLASH ==
                                    binary:part(Path, {byte_size(Path)-1, 1})),
                {none, HasTermSlash, Path, Req1};
            {BinParam, Req1} ->
                NewPath = case binary:part(Path, {byte_size(Path)-1, 1}) of
                              ?BIN_SLASH -> Path;
                              _Else      -> <<Path/binary, ?BIN_SLASH/binary>>
                          end,
                {BinParam, true, NewPath, Req1}
        end,

    TokenLen = length(binary:split(Path2, [?BIN_SLASH], [global, trim])),
    {HTTPMethod0, _} = cowboy_http_req:method(Req),

    case cowboy_http_req:qs_val(?HTTP_QS_BIN_ACL, Req2) of
        {undefined, _} ->
            ReqParams = request_params(
                          Req2, #req_params{path                   = Path2,
                                            token_length           = TokenLen,
                                            min_layers             = NumOfMinLayers,
                                            max_layers             = NumOfMaxLayers,
                                            qs_prefix              = Prefix,
                                            has_inner_cache        = HasInnerCache,
                                            is_dir                 = IsDir,
                                            acceptable_max_obj_len = AcceptableObjLen,
                                            chunked_obj_len        = ChunkedObjLen,
                                            threshold_obj_len      = ThresholdObjLen}),

            AuthRet = auth1(UseS3API, Req2, HTTPMethod0, Path2, TokenLen),
            handle1(AuthRet, Req2, HTTPMethod0, Path2, ReqParams, State);
        _ ->
            {ok, Req3} = cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req2),
            {ok, Req3, State}
    end.


%% @doc Handle a request
%% @private
handle1({error, _Cause}, Req0,_,_,_,State) ->
    {ok, Req1} = cowboy_http_req:reply(?HTTP_ST_FORBIDDEN, [?SERVER_HEADER], Req0),
    {ok, Req1, State};

handle1({ok,_AccessKeyId}, Req0,_,_, #req_params{path = Path0,
                                                 is_upload = true}, State) ->
    %% Insert a metadata into the storage-cluster
    %% @TODO

    %% Response xml to a client
    Now = leo_date:now(),
    [Bucket|Path1] = leo_misc:binary_tokens(Path0, ?BIN_SLASH),
    AmzRequestId = erlang:md5(<< Path0/binary, Now:64 >>),
    XML = gen_upload_initiate_xml(Bucket, Path1, AmzRequestId),

    {ok, Req1} = cowboy_http_req:set_resp_body(XML, Req0),
    {ok, Req2} = cowboy_http_req:reply(?HTTP_ST_OK, [?SERVER_HEADER], Req1),
    {ok, Req2, State};

handle1({ok, AccessKeyId}, Req0, HTTPMethod0, Path, Params, State) ->
    HTTPMethod1 = case HTTPMethod0 of
                      ?HTTP_POST -> ?HTTP_PUT;
                      Other      -> Other
                  end,

    case catch exec1(HTTPMethod1, Req0, Path, Params#req_params{access_key_id = AccessKeyId}) of
        {'EXIT', Reason} ->
            ?error("handle1/6", "path:~p, cause:~p", [Path, Reason]),
            {ok, Req1} = cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req0),
            {ok, Req1, State};
        {ok, Req1} ->
            Req2 = cowboy_http_req:compact(Req1),
            {ok, Req2, State}
    end.


%% @doc Terminater
terminate(_Req, _State) ->
    ok.


%%--------------------------------------------------------------------
%% Callbacks
%%--------------------------------------------------------------------
%% @doc Handle request
%% @private
onrequest(#cache_condition{expire = Expire}) ->
    fun(Req) ->
            {Method, _} = cowboy_http_req:method(Req),
            onrequest_fun1(Method, Req, Expire)
    end.


%% @doc Handle request
%% @private
onrequest_fun1(?HTTP_GET, Req, Expire) ->
    Key = gen_key(Req),
    Ret = ecache_api:get(Key),
    onrequest_fun2(Req, Expire, Key, Ret);
onrequest_fun1(_, Req, _) ->
    Req.


%% @doc Handle request
%% @private
onrequest_fun2(Req,_Expire,_Key, not_found) ->
    Req;
onrequest_fun2(Req, Expire, Key, {ok, CachedObj}) ->
    #cache{mtime        = MTime,
           content_type = ContentType,
           etag         = Checksum,
           body         = Body} = binary_to_term(CachedObj),

    Now = leo_date:now(),
    Diff = Now - MTime,

    case (Diff > Expire) of
        true ->
            _ = ecache_api:delete(Key),
            Req;
        false ->
            LastModified = leo_http:rfc1123_date(MTime),
            Date  = cowboy_clock:rfc1123(),
            Heads = [?SERVER_HEADER,
                     {?HTTP_HEAD_ATOM_LAST_MODIFIED, LastModified},
                     {?HTTP_HEAD_ATOM_CONTENT_TYPE,  ContentType},
                     {?HTTP_HEAD_ATOM_DATE,          Date},
                     {?HTTP_HEAD_ATOM_AGE,           integer_to_list(Diff)},
                     {?HTTP_HEAD_BIN_ETAG4AWS,       lists:append(["\"",leo_hex:integer_to_hex(Checksum, 32),"\""])},
                     {?HTTP_HEAD_ATOM_CACHE_CTRL,    lists:append(["max-age=",integer_to_list(Expire)])}
                    ],
            IMSSec = case cowboy_http_req:parse_header(?HTTP_HEAD_ATOM_IF_MODIFIED_SINCE, Req) of
                         {undefined, _} ->
                             0;
                         {IMSDateTime, _} ->
                             calendar:datetime_to_gregorian_seconds(IMSDateTime)
                     end,
            case IMSSec of
                MTime ->
                    {ok, Req2} = cowboy_http_req:reply(?HTTP_ST_NOT_MODIFIED, Heads, Req),
                    Req2;
                _ ->
                    {ok, Req2} = cowboy_http_req:set_resp_body(Body, Req),
                    {ok, Req3} = cowboy_http_req:reply(?HTTP_ST_OK, Heads, Req2),
                    Req3
            end
    end.


%% @doc Handle response
%% @private
onresponse(#cache_condition{expire = Expire} = Config) ->
    fun(?HTTP_ST_OK, Headers, Req) when Req#http_req.method == ?HTTP_GET ->
            Key = gen_key(Req),

            case lists:all(fun(Fun) ->
                                   Fun(Key, Config, Headers, Req)
                           end, [fun is_cachable_req1/4,
                                 fun is_cachable_req2/4,
                                 fun is_cachable_req3/4]) of
                true ->
                    Now = leo_date:now(),
                    ContentType = case lists:keyfind(?HTTP_HEAD_BIN_CONTENT_TYPE, 1, Headers) of
                                      false ->
                                          ?HTTP_CTYPE_OCTET_STREAM;
                                      {_, Val} ->
                                          Val
                                  end,
                    {ok, Body, _} = cowboy_http_req:get_resp_body(Req),

                    Bin = term_to_binary(
                            #cache{mtime        = Now,
                                   etag         = leo_hex:binary_to_integer(erlang:md5(Body)),
                                   content_type = ContentType,
                                   body         = Body}),
                    _ = ecache_api:put(Key, Bin),

                    Headers2 = lists:keydelete(?HTTP_HEAD_BIN_LAST_MODIFIED, 1, Headers),
                    Headers3 = [{?HTTP_HEAD_ATOM_CACHE_CTRL, lists:append(["max-age=",integer_to_list(Expire)])},
                                {?HTTP_HEAD_ATOM_LAST_MODIFIED, leo_http:rfc1123_date(Now)}
                                |Headers2],
                    {ok, Req2} = cowboy_http_req:reply(?HTTP_ST_OK, Headers3, Req),
                    Req2;
                false ->
                    Req#http_req{resp_body = <<>>}
            end;
       (_, _, Req)  ->
            Req#http_req{resp_body = <<>>}
    end.


%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------
%% @doc Retrieve header values from a request
%%      Set request params
%% @private
request_params(Req, Params) ->
    IsUpload  = case cowboy_http_req:qs_val(?HTTP_QS_BIN_UPLOADS, Req) of
                    {undefined, _} -> false;
                    _ -> true
                end,
    {Range,_} = cowboy_http_req:header(?HTTP_HEAD_ATOM_RANGE, Req),
    Params#req_params{is_upload    = IsUpload,
                      range_header = Range}.


%% @doc Judge cachable request
%% @private
is_cachable_req1(_Key, #cache_condition{max_content_len = MaxLen}, Headers, Req) ->
    {ok, Body, _} = cowboy_http_req:get_resp_body(Req),

    HasNOTCacheControl = (false == lists:keyfind(?HTTP_HEAD_BIN_CACHE_CTRL, 1, Headers)),
    HasNOTCacheControl  andalso
        is_binary(Body) andalso
        size(Body) > 0  andalso
        size(Body) < MaxLen.

%% @doc Judge cachable request
%% @private
is_cachable_req2(_Key, #cache_condition{path_patterns = []}, _Headers, _Req) ->
    true;
is_cachable_req2(_Key, #cache_condition{path_patterns = undefined}, _Headers, _Req) ->
    true;
is_cachable_req2( Key, #cache_condition{path_patterns = PathPatterns}, _Headers, _Req) ->
    Res = lists:any(fun(Path) ->
                            nomatch /= re:run(Key, Path)
                    end, PathPatterns),
    Res.


%% @doc Judge cachable request
%% @private
is_cachable_req3(_, #cache_condition{content_types = []}, _Headers, _Req) ->
    true;
is_cachable_req3(_, #cache_condition{content_types = undefined}, _Headers, _Req) ->
    true;
is_cachable_req3(_Key, #cache_condition{content_types = ContentTypeList}, Headers, _Req) ->
    case lists:keyfind(?HTTP_HEAD_BIN_CONTENT_TYPE, 1, Headers) of
        false ->
            false;
        {_, ContentType} ->
            lists:member(ContentType, ContentTypeList)
    end.


%% Compile Options:
%%
-compile({inline, [gen_key/1, exec1/4, exec2/5, put1/4, put2/5, put3/3, put4/2,
                   get_header/2, auth1/5, auth2/4, http_verb/1]}).

%% @doc Create a key
%% @private
gen_key(Req) ->
    EndPoints1 = case leo_s3_endpoint:get_endpoints() of
                     {ok, EndPoints0} ->
                         lists:map(fun({endpoint,EP,_}) -> EP end, EndPoints0);
                     _ -> []
                 end,
    {Host,    _} = cowboy_http_req:raw_host(Req),
    {RawPath, _} = cowboy_http_req:raw_path(Req),
    Path = cowboy_http:urldecode(RawPath),
    leo_http:key(EndPoints1, Host, Path).


%% ---------------------------------------------------------------------
%% INVALID OPERATION
%% ---------------------------------------------------------------------
%% @doc Constraint violation.
%% @private
exec1(_HTTPMethod, Req,_Key, #req_params{token_length = Len,
                                         max_layers   = Max}) when Len > Max ->
    cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);

%% ---------------------------------------------------------------------
%% For BUCKET-OPERATION
%% ---------------------------------------------------------------------
%% @doc GET operation on buckets & Dirs.
%% @private
exec1(?HTTP_GET, Req, Key, #req_params{is_dir        = true,
                                       access_key_id = AccessKeyId,
                                       qs_prefix     = Prefix}) ->
    case leo_s3_http_bucket:get_bucket_list(AccessKeyId, Key, none, none, 1000, Prefix) of
        {ok, Meta, XML} when is_list(Meta) == true ->
            {ok, Req2} = cowboy_http_req:set_resp_body(XML, Req),
            cowboy_http_req:reply(?HTTP_ST_OK, [?SERVER_HEADER,
                                                {?HTTP_HEAD_ATOM_CONTENT_TYPE, ?HTTP_CTYPE_XML},
                                                {?HTTP_HEAD_ATOM_DATE, cowboy_clock:rfc1123()}
                                               ], Req2);
        {error, not_found} ->
            cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end;

%% @doc PUT operation on buckets.
%% @private
exec1(?HTTP_PUT, Req, Key, #req_params{token_length  = 1,
                                       access_key_id = AccessKeyId}) ->
    Bucket = case (?BIN_SLASH == binary:part(Key, {byte_size(Key)-1, 1})) of
                 true ->
                     binary:part(Key, {0, byte_size(Key) -1});
                 false ->
                     Key
             end,

    case leo_s3_http_bucket:put_bucket(AccessKeyId, Bucket) of
        ok ->
            cowboy_http_req:reply(?HTTP_ST_OK, [?SERVER_HEADER], Req);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end;

%% @doc DELETE operation on buckets.
%% @private
exec1(?HTTP_DELETE, Req, Key, #req_params{token_length  = 1,
                                          access_key_id = AccessKeyId}) ->
    case leo_s3_http_bucket:delete_bucket(AccessKeyId, Key) of
        ok ->
            cowboy_http_req:reply(?HTTP_ST_NO_CONTENT, [?SERVER_HEADER], Req);
        not_found ->
            cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end;

%% @doc HEAD operation on buckets.
%% @private
exec1(?HTTP_HEAD, Req, Key, #req_params{token_length  = 1,
                                        access_key_id = AccessKeyId}) ->
    case leo_s3_http_bucket:head_bucket(AccessKeyId, Key) of
        ok ->
            cowboy_http_req:reply(?HTTP_ST_OK, [?SERVER_HEADER], Req);
        not_found ->
            cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end;

%% ---------------------------------------------------------------------
%% For OBJECT-OPERATION
%% ---------------------------------------------------------------------
%% @doc GET operation on Object with Range Header.
%% @private
exec1(?HTTP_GET, Req, Key, #req_params{is_dir       = false,
                                       range_header = RangeHeader}) when RangeHeader /= undefined ->
    %% TODO - Will support this function with v0.12.1
    [_,ByteRangeSpec|_] = string:tokens(binary_to_list(RangeHeader), "="),
    ByteRangeSet = string:tokens(ByteRangeSpec, "-"),
    {Start, End} = case length(ByteRangeSet) of
                       1 ->
                           [StartStr|_] = ByteRangeSet,
                           {list_to_integer(StartStr), 0};
                       2 ->
                           [StartStr,EndStr|_] = ByteRangeSet,
                           {list_to_integer(StartStr), list_to_integer(EndStr) + 1};
                       _ ->
                           {undefined, undefined}
                   end,
    case Start of
        undefined ->
            cowboy_http_req:reply(416, [?SERVER_HEADER], Req);
        _ ->
            case leo_gateway_rpc_handler:get(Key, Start, End) of
                {ok, _Meta, RespObject} ->
                    Mime = leo_mime:guess_mime(Key),
                    {ok, Req2} = cowboy_http_req:set_resp_body(RespObject, Req),
                    cowboy_http_req:reply(206,
                                          [?SERVER_HEADER,
                                           {?HTTP_HEAD_ATOM_CONTENT_TYPE,  Mime}],
                                          Req2);
                {error, not_found} ->
                    cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);
                {error, ?ERR_TYPE_INTERNAL_ERROR} ->
                    cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
                {error, timeout} ->
                    cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
            end
    end;

%% @doc GET operation on Object if inner cache is enabled.
%% @private
exec1(?HTTP_GET = HTTPMethod, Req, Key, #req_params{is_dir = false,
                                                    has_inner_cache = true} = Params) ->
    case ecache_api:get(Key) of
        not_found ->
            exec1(HTTPMethod, Req, Key, Params);
        {ok, CachedObj} ->
            Cached = binary_to_term(CachedObj),
            exec2(HTTPMethod, Req, Key, Params, Cached)
    end;

%% @doc GET operation on Object.
%% @private
exec1(?HTTP_GET, Req, Key, #req_params{is_dir = false,
                                       has_inner_cache = HasInnerCache}) ->
    case leo_gateway_rpc_handler:get(Key) of
        %% For regular case (NOT a chunked object)
        {ok, #metadata{cnumber = 0} = Meta, RespObject} ->
            Mime = leo_mime:guess_mime(Key),

            case HasInnerCache of
                true ->
                    BinVal = term_to_binary(#cache{etag = Meta#metadata.checksum,
                                                   mtime = Meta#metadata.timestamp,
                                                   content_type = Mime,
                                                   body = RespObject}),
                    _ = ecache_api:put(Key, BinVal);
                false ->
                    void
            end,
            {ok, Req2} = cowboy_http_req:set_resp_body(RespObject, Req),
            cowboy_http_req:reply(?HTTP_ST_OK,
                                  [?SERVER_HEADER,
                                   {?HTTP_HEAD_ATOM_CONTENT_TYPE,  Mime},
                                   {?HTTP_HEAD_BIN_ETAG4AWS, lists:append(["\"",
                                                                           leo_hex:integer_to_hex(Meta#metadata.checksum, 32),
                                                                           "\""])},
                                   {?HTTP_HEAD_ATOM_LAST_MODIFIED, leo_http:rfc1123_date(Meta#metadata.timestamp)}],
                                  Req2);

        %% For a chunked object.
        {ok, #metadata{cnumber = TotalChunkedObjs}, _RespObject} ->
            {ok, Pid}  = leo_gateway_large_object_handler:start_link(),
            {ok, Req2} = cowboy_http_req:chunked_reply(?HTTP_ST_OK, [?SERVER_HEADER], Req),

            Ret = leo_gateway_large_object_handler:get(Pid, Key, TotalChunkedObjs, Req2),
            catch leo_gateway_large_object_handler:stop(Pid),

            case Ret of
                {ok, Req3} ->
                    {ok, Req3};
                {error, Cause} ->
                    ?error("exec1/4", "path:~p, cause:~p", [binary_to_list(Key), Cause]),
                    cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req)
            end;
        {error, not_found} ->
            cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end;


%% @doc HEAD operation on Object.
%% @private
exec1(?HTTP_HEAD, Req, Key, _Params) ->
    case leo_gateway_rpc_handler:head(Key) of
        {ok, #metadata{del = 0} = Meta} ->
            TimeStamp = leo_http:rfc1123_date(Meta#metadata.timestamp),
            Headers   = [?SERVER_HEADER,
                         {?HTTP_HEAD_ATOM_CONTENT_TYPE,   leo_mime:guess_mime(Key)},
                         {?HTTP_HEAD_BIN_ETAG4AWS, lists:append(["\"",
                                                                 leo_hex:integer_to_hex(Meta#metadata.checksum, 32),
                                                                 "\""
                                                                ])},
                         {?HTTP_HEAD_ATOM_CONTENT_LENGTH, erlang:integer_to_list(Meta#metadata.dsize)},
                         {?HTTP_HEAD_ATOM_LAST_MODIFIED,  TimeStamp}],
            cowboy_http_req:reply(?HTTP_ST_OK, Headers, Req);
        {ok, #metadata{del = 1}} ->
            cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);
        {error, not_found} ->
            cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end;

%% @doc DELETE operation on Object.
%% @private
exec1(?HTTP_DELETE, Req, Key, _Params) ->
    case leo_gateway_rpc_handler:delete(Key) of
        ok ->
            cowboy_http_req:reply(?HTTP_ST_NO_CONTENT, [?SERVER_HEADER], Req);
        {error, not_found} ->
            cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end;

%% @doc POST/PUT operation on Objects.
%% @private
exec1(?HTTP_PUT, Req, Key, Params) ->
    put1(get_header(Req, ?HTTP_HEAD_BIN_X_AMZ_META_DIRECTIVE), Req, Key, Params);

%% @doc invalid request.
%% @private
exec1(_, Req, _, _) ->
    cowboy_http_req:reply(?HTTP_ST_BAD_REQ, [?SERVER_HEADER], Req).


%% @doc GET operation with Etag
%% @private
exec2(?HTTP_GET, Req, Key, #req_params{is_dir = false, has_inner_cache = true}, Cached) ->
    case leo_gateway_rpc_handler:get(Key, Cached#cache.etag) of
        {ok, match} ->
            {ok, Req2} = cowboy_http_req:set_resp_body(Cached#cache.body, Req),
            cowboy_http_req:reply(?HTTP_ST_OK,
                                  [?SERVER_HEADER,
                                   {?HTTP_HEAD_ATOM_CONTENT_TYPE,  Cached#cache.content_type},
                                   {?HTTP_HEAD_BIN_ETAG4AWS, lists:append(["\"",
                                                                           leo_hex:integer_to_hex(Cached#cache.etag, 32),
                                                                           "\""])},
                                   {?HTTP_HEAD_ATOM_LAST_MODIFIED, leo_http:rfc1123_date(Cached#cache.mtime)},
                                   {?HTTP_HEAD_BIN_X_FROM_CACHE,  <<"True">>}],
                                  Req2);
        {ok, Meta, RespObject} ->
            Mime = leo_mime:guess_mime(Key),
            BinVal = term_to_binary(#cache{etag = Meta#metadata.checksum,
                                           mtime = Meta#metadata.timestamp,
                                           content_type = Mime,
                                           body = RespObject}),

            _ = ecache_api:put(Key, BinVal),

            {ok, Req2} = cowboy_http_req:set_resp_body(RespObject, Req),
            cowboy_http_req:reply(?HTTP_ST_OK,
                                  [?SERVER_HEADER,
                                   {?HTTP_HEAD_ATOM_CONTENT_TYPE,  Mime},
                                   {?HTTP_HEAD_BIN_ETAG4AWS, lists:append(["\"",
                                                                           leo_hex:integer_to_hex(Meta#metadata.checksum, 32),
                                                                           "\""])},
                                   {?HTTP_HEAD_ATOM_LAST_MODIFIED, leo_http:rfc1123_date(Meta#metadata.timestamp)}],
                                  Req2);
        {error, not_found} ->
            cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end.


%% @doc POST/PUT operation on Objects. NORMAL
%% @private
put1(?BIN_EMPTY, Req, Key, Params) ->
    {Size0, _} = cowboy_http_req:body_length(Req),

    case (Size0 >= Params#req_params.threshold_obj_len) of
        true when Size0 >= Params#req_params.acceptable_max_obj_len ->
            cowboy_http_req:reply(?HTTP_ST_BAD_REQ, [?SERVER_HEADER], Req);
        true ->
            put_large_object(Req, Key, Size0, Params);
        false ->
            {Size1, Bin1, Req1} =
                case cowboy_http_req:has_body(Req) of
                    {true, _} ->
                        {ok, Bin0, Req0} = cowboy_http_req:body(Req),
                        {Size0, Bin0, Req0};
                    {false, _} ->
                        {0, ?BIN_EMPTY, Req}
                end,

            case leo_gateway_rpc_handler:put(Key, Bin1, Size1) of
                {ok, ETag} ->
                    cowboy_http_req:reply(?HTTP_ST_OK, [?SERVER_HEADER,
                                                        {?HTTP_HEAD_BIN_ETAG4AWS,
                                                         lists:append(["\"",
                                                                       leo_hex:integer_to_hex(ETag, 32),
                                                                       "\""])}
                                                       ], Req1);
                {error, ?ERR_TYPE_INTERNAL_ERROR} ->
                    cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req1);
                {error, timeout} ->
                    cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req1)
            end
    end;


%% @doc POST/PUT operation on Objects. COPY/REPLACE
%% @private
put1(Directive, Req, Key, _Params) ->
    CS = get_header(Req, ?HTTP_HEAD_BIN_X_AMZ_COPY_SOURCE),

    %% need to trim head '/' when cooperating with s3fs(-c)
    CS2 = case binary:part(CS, {0, 1}) of
              ?BIN_SLASH ->
                  binary:part(CS, {1, byte_size(CS) -1});
              _ ->
                  CS
          end,

    case leo_gateway_rpc_handler:get(CS2) of
        {ok, Meta, RespObject} ->
            put2(Directive, Req, Key, Meta, RespObject);
        {error, not_found} ->
            cowboy_http_req:reply(?HTTP_ST_NOT_FOUND, [?SERVER_HEADER], Req);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end.

%% @doc POST/PUT operation on Objects. COPY
%% @private
put2(Directive, Req, Key, Meta, Bin) ->
    Size = size(Bin),

    case leo_gateway_rpc_handler:put(Key, Bin, Size) of
        {ok, _ETag} when Directive == ?HTTP_HEAD_BIN_X_AMZ_META_DIRECTIVE_COPY ->
            resp_copy_obj_xml(Req, Meta);
        {ok, _ETag} when Directive == ?HTTP_HEAD_BIN_X_AMZ_META_DIRECTIVE_REPLACE ->
            put3(Req, Key, Meta);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end.


%% @doc POST/PUT operation on Objects. REPLACE
%% @private
put3(Req, Key, Meta) ->
    KeyList = binary_to_list(Key),
    case KeyList == Meta#metadata.key of
        true  -> resp_copy_obj_xml(Req, Meta);
        false -> put4(Req, Meta)
    end.

put4(Req, Meta) ->
    KeyBin = list_to_binary(Meta#metadata.key),
    case leo_gateway_rpc_handler:delete(KeyBin) of
        ok ->
            resp_copy_obj_xml(Req, Meta);
        {error, not_found} ->
            resp_copy_obj_xml(Req, Meta);
        {error, ?ERR_TYPE_INTERNAL_ERROR} ->
            cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req);
        {error, timeout} ->
            cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req)
    end.


%% @doc
%% @private
put_large_object(Req0, Key, Size0, Params)->
    %% PUT children's data (Chunked objects)
    %%
    {ok, Pid}  = leo_gateway_large_object_handler:start_link(),
    ChunkedSize = Params#req_params.chunked_obj_len,

    Ret = case cowboy_http_req:body(
                 Req0, Params#req_params.chunked_obj_len,
                 fun(_Index, _Size, _Bin) ->
                         catch leo_gateway_large_object_handler:put(Pid, Key, _Index, _Size, _Bin)
                 end) of
              {ok, TotalLength, TotalChunckedObjs, Req1} ->
                  %% PUT parent's data
                  %%
                  case catch leo_gateway_large_object_handler:result(Pid) of
                      {ok, Digest0} when Size0 == TotalLength ->
                          Digest1 = leo_hex:binary_to_integer(Digest0),

                          case leo_gateway_rpc_handler:put(
                                 Key, ?BIN_EMPTY, Size0, ChunkedSize, TotalChunckedObjs, Digest1) of
                              {ok, _ETag} ->
                                  cowboy_http_req:reply(?HTTP_ST_OK, [?SERVER_HEADER], Req1);
                              {error, ?ERR_TYPE_INTERNAL_ERROR} ->
                                  cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req1);
                              {error, timeout} ->
                                  cowboy_http_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, [?SERVER_HEADER], Req1)
                          end;
                      {_, _Cause} ->
                          ok = leo_gateway_large_object_handler:rollback(Pid, Key, TotalChunckedObjs),
                          cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req0)
                  end;
              {error, {NumOfChunkedObjs, Cause}} ->
                  ?error("handle_cast/2", "key:~s, cause:~p", [binary_to_list(Key), Cause]),

                  ok = leo_gateway_large_object_handler:rollback(Pid, Key, NumOfChunkedObjs),
                  cowboy_http_req:reply(?HTTP_ST_INTERNAL_ERROR, [?SERVER_HEADER], Req0)
          end,

    catch leo_gateway_large_object_handler:stop(Pid),
    Ret.


%% @doc getter helper function. return "" if specified header is undefined
%% @private
get_header(Req, Key) ->
    case cowboy_http_req:header(Key, Req) of
        {undefined, _} ->
            ?BIN_EMPTY;
        {Bin, _} ->
            Bin
    end.


%% @doc
%% @private
resp_copy_obj_xml(Req, Meta) ->
    XML = io_lib:format(?XML_COPY_OBJ_RESULT,
                        [leo_http:web_date(Meta#metadata.timestamp),
                         leo_hex:integer_to_hex(Meta#metadata.checksum, 32)]),
    {ok, Req2} = cowboy_http_req:set_resp_body(XML, Req),
    cowboy_http_req:reply(?HTTP_ST_OK, [?SERVER_HEADER,
                                        {?HTTP_HEAD_ATOM_CONTENT_TYPE, ?HTTP_CTYPE_XML},
                                        {?HTTP_HEAD_ATOM_DATE,         cowboy_clock:rfc1123()}
                                       ], Req2).


%% @doc Authentication
%% @private
auth1(false,_Req,_HTTPMethod,_Path,_TokenLen) ->
    {ok, []};
auth1(true,  Req, HTTPMethod, Path, TokenLen) when TokenLen =< 1 ->
    auth2(Req, HTTPMethod, Path, TokenLen);
auth1(true,  Req, ?HTTP_POST = HTTPMethod, Path, TokenLen) when TokenLen > 1 ->
    auth2(Req, HTTPMethod, Path, TokenLen);
auth1(true,  Req, ?HTTP_PUT = HTTPMethod, Path, TokenLen) when TokenLen > 1 ->
    auth2(Req, HTTPMethod, Path, TokenLen);
auth1(true,  Req, ?HTTP_DELETE = HTTPMethod, Path, TokenLen) when TokenLen > 1 ->
    auth2(Req, HTTPMethod, Path, TokenLen);
auth1(_,_,_,_,_) ->
    {ok, []}.

auth2(Req, HTTPMethod, Path, TokenLen) ->
    %% bucket operations must be needed to auth
    %% AND alter object operations as well
    case cowboy_http_req:header(?HTTP_HEAD_ATOM_AUTHORIZATION, Req) of
        {undefined, _} ->
            {error, undefined};
        {AuthorizationBin, _} ->
            Bucket = case (TokenLen >= 1) of
                         true  -> hd(leo_misc:binary_tokens(Path, ?BIN_SLASH));
                         false -> ?BIN_EMPTY
                     end,

            IsCreateBucketOp = (TokenLen == 1 andalso HTTPMethod == ?HTTP_PUT),
            {RawUri,      _} = cowboy_http_req:raw_path(Req),
            {QueryString, _} = cowboy_http_req:raw_qs(Req),
            {Headers,     _} = cowboy_http_req:headers(Req),

            URI = case (byte_size(QueryString) > 0 andalso
                        QueryString == ?HTTP_QS_BIN_UPLOADS) of
                      true  -> << RawUri/binary, "?", QueryString/binary >>;
                      false -> RawUri
                  end,

            SignParams = #sign_params{http_verb    = http_verb(HTTPMethod),
                                      content_md5  = get_header(Req, ?HTTP_HEAD_ATOM_CONTENT_MD5),
                                      content_type = get_header(Req, ?HTTP_HEAD_ATOM_CONTENT_TYPE),
                                      date         = get_header(Req, ?HTTP_HEAD_ATOM_DATE),
                                      bucket       = Bucket,
                                      uri          = URI,
                                      query_str    = QueryString,
                                      amz_headers  = leo_http:get_amz_headers4cow(Headers)},
            leo_s3_auth:authenticate(AuthorizationBin, SignParams, IsCreateBucketOp)
    end.


%% @doc Replace data-type from atom() to binary()
%% @private
-spec(http_verb(atom()) ->
             binary()).
http_verb(?HTTP_GET)    -> <<"GET">>;
http_verb(?HTTP_POST)   -> <<"POST">>;
http_verb(?HTTP_PUT)    -> <<"PUT">>;
http_verb(?HTTP_DELETE) -> <<"DELETE">>;
http_verb(?HTTP_HEAD)   -> <<"HEAD">>.


%% @doc Generate an update-initiate xml
%% @private
-spec(gen_upload_initiate_xml(binary(), list(binary()), binary()) ->
             list()).
gen_upload_initiate_xml(Bucket, Path, UploadId) ->
    BucketStr = binary_to_list(Bucket),
    KeyStr    = lists:foldl(fun(I, [])  -> binary_to_list(I);
                               (I, Acc) -> Acc ++ "/" ++ binary_to_list(I)
                            end, [], Path),
    io_lib:format(?XML_UPLOAD_INITIATION, [BucketStr, KeyStr, UploadId]).

