%%======================================================================
%%
%% Leo Gateway
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
%% Leo Gateway Rest-API
%% @doc
%% @end
%%======================================================================
-module(leo_gateway_rest_api).

-author('Yosuke Hara').

-behaviour(leo_gateway_http_behaviour).

-export([start/2, stop/0,
         init/3, handle/2, terminate/3]).
-export([onrequest/1, onresponse/1]).
-export([get_bucket/3, put_bucket/3, delete_bucket/3, head_bucket/3,
         get_object/3, put_object/3, delete_object/3, head_object/3,
         get_object_with_cache/4, range_object/3]).

-include("leo_gateway.hrl").
-include("leo_http.hrl").
-include_lib("leo_logger/include/leo_logger.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile({inline, [handle/2, handle_1/3]}).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
start(Sup, HttpOptions) ->
    leo_gateway_http_commons:start(Sup, HttpOptions).

stop() ->
    cowboy:stop_listener(?MODULE),
    cowboy:stop_listener(list_to_atom(lists:append([?MODULE_STRING, "_ssl"]))),
    ok.


%% @doc Initializer
init({_Any, http}, Req, Opts) ->
    {ok, Req, Opts}.


%% @doc Handle a request
%% @callback
handle(Req, State) ->
    Key = gen_key(Req),
    handle_1(Req, State, Key).


%% @doc Terminater
terminate(_Reason, _Req, _State) ->
    ok.


%%--------------------------------------------------------------------
%% Callbacks from Cowboy
%%--------------------------------------------------------------------
%% @doc Handle request
%%
onrequest(CacheCondition) ->
    leo_gateway_http_commons:onrequest(CacheCondition, fun gen_key/1).


%% @doc Handle response
%%
onresponse(CacheCondition) ->
    leo_gateway_http_commons:onrequest(CacheCondition, fun gen_key/1).


%%--------------------------------------------------------------------
%% Callbacks from HTTP-Handler
%%--------------------------------------------------------------------
%% @doc GET buckets and dirs
get_bucket(Req,_Key,_Params) ->
    ?reply_bad_request([?SERVER_HEADER], Req).


%% @doc PUT buckets and dirs
put_bucket(Req,_Key,_Params) ->
    ?reply_bad_request([?SERVER_HEADER], Req).


%% @doc DELETE buckets and dirs
delete_bucket(Req,_Key,_Params) ->
    ?reply_bad_request([?SERVER_HEADER], Req).

%% @doc HEAD buckets and dirs
head_bucket(Req,_Key,_Params) ->
    ?reply_bad_request([?SERVER_HEADER], Req).


%% ---------------------------------------------------------------------
%% For OBJECT-OPERATION
%% ---------------------------------------------------------------------
%% @doc GET operation on Objects
-spec(get_object(any(), binary(), #req_params{}) ->
             {ok, any()}).
get_object(Req, Key, Params) ->
    leo_gateway_http_commons:get_object(Req, Key, Params).


%% @doc GET operation on Objects
-spec(get_object_with_cache(any(), binary(), #cache{}, #req_params{}) ->
             {ok, any()}).
get_object_with_cache(Req, Key, CacheObj, Params) ->
    leo_gateway_http_commons:get_object_with_cache(Req, Key, CacheObj, Params).


%% @doc POST/PUT operation on Objects
-spec(put_object(any(), binary(), #req_params{}) ->
             {ok, any()}).
put_object(Req, Key, Params) ->
    leo_gateway_http_commons:put_object(Req, Key, Params).


%% @doc DELETE operation on Objects
-spec(delete_object(any(), binary(), #req_params{}) ->
             {ok, any()}).
delete_object(Req, Key, Params) ->
    leo_gateway_http_commons:delete_object(Req, Key, Params).


%% @doc HEAD operation on Objects
-spec(head_object(any(), binary(), #req_params{}) ->
             {ok, any()}).
head_object(Req, Key, Params) ->
    leo_gateway_http_commons:head_object(Req, Key, Params).


%% @doc RANGE-Query operation on Objects
-spec(range_object(any(), binary(), #req_params{}) ->
             {ok, any()}).
range_object(Req,_Key,_Params) ->
    ?reply_bad_request([?SERVER_HEADER], Req).


%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------
%% @doc Create a key
%% @private
gen_key(Req) ->
    {Path1, _} = cowboy_req:path(Req),
    Path3 = case Path1 of
                << "/", Path2/binary >> ->
                    Path2;
                _ ->
                    Path1
            end,
    cowboy_http:urldecode(Path3).


%% @doc Hande an http-request
%% @private
handle_1(Req, [{NumOfMinLayers, NumOfMaxLayers}, HasInnerCache, Props] = State, Path) ->
    TokenLen   = length(binary:split(Path, [?BIN_SLASH], [global, trim])),
    HTTPMethod = cowboy_req:get(method, Req),

    case (TokenLen >= NumOfMinLayers) of
        true ->
            ReqParams  = #req_params{handler           = ?MODULE,
                                     path              = Path,
                                     token_length      = TokenLen,
                                     min_layers        = NumOfMinLayers,
                                     max_layers        = NumOfMaxLayers,
                                     has_inner_cache   = HasInnerCache,
                                     is_cached         = true,
                                     max_chunked_objs  = Props#http_options.max_chunked_objs,
                                     max_len_for_obj   = Props#http_options.max_len_for_obj,
                                     chunked_obj_len   = Props#http_options.chunked_obj_len,
                                     threshold_obj_len = Props#http_options.threshold_obj_len},
            handle_2(Req, HTTPMethod, Path, ReqParams, State);
        false when HTTPMethod == ?HTTP_GET ->
            ?reply_not_found([?SERVER_HEADER], Req);
        false  ->
            ?reply_bad_request([?SERVER_HEADER], Req)
    end.


handle_2(Req, ?HTTP_POST, Path, Params, State) ->
    handle_2(Req, ?HTTP_PUT, Path, Params, State);
handle_2(Req1, HTTPMethod, Path, Params, State) ->
    case catch leo_gateway_http_req_handler:handle(HTTPMethod, Req1, Path, Params) of
        {'EXIT', Cause} ->
            ?error("handle1/5", "path:~s, cause:~p", [binary_to_list(Path), Cause]),
            {ok, Req2} = ?reply_internal_error([?SERVER_HEADER], Req1),
            {ok, Req2, State};
        {ok, Req2} ->
            Req3 = cowboy_req:compact(Req2),
            {ok, Req3, State}
    end.

