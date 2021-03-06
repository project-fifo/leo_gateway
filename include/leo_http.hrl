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
%% Leo S3 HTTP
%% @doc
%% @end
%%======================================================================
%% HTTP METHODS
-define(HTTP_GET,        <<"GET">>).
-define(HTTP_POST,       <<"POST">>).
-define(HTTP_PUT,        <<"PUT">>).
-define(HTTP_DELETE,     <<"DELETE">>).
-define(HTTP_HEAD,       <<"HEAD">>).

%% HTTP-RELATED
-define(SERVER_HEADER,   {<<"server">>,<<"LeoFS">>}).
-define(STR_NEWLINE,     "\n").
-define(STR_SLASH,       "/").
-define(BIN_SLASH,       <<"/">>).
-define(BIN_EMPTY,       <<>>).

-define(ERR_TYPE_INTERNAL_ERROR, internal_server_error).

%% HTTP HEADER
-define(HTTP_HEAD_AGE,                <<"age">>).
-define(HTTP_HEAD_AUTHORIZATION,      <<"authorization">>).
-define(HTTP_HEAD_CACHE_CTRL,         <<"cache-control">>).
-define(HTTP_HEAD_CONTENT_LENGTH,     <<"content-length">>).
-define(HTTP_HEAD_CONTENT_MD5,        <<"content-md5">>).
-define(HTTP_HEAD_CONTENT_TYPE,       <<"content-type">>).
-define(HTTP_HEAD_DATE,               <<"date">>).
-define(HTTP_HEAD_ETAG,               <<"etag">>).
-define(HTTP_HEAD_IF_MODIFIED_SINCE,  <<"if-modified-since">>).
-define(HTTP_HEAD_LAST_MODIFIED,      <<"last-modified">>).
-define(HTTP_HEAD_PREFIX,             <<"prefix">>).
-define(HTTP_HEAD_RANGE,              <<"range">>).

-define(HTTP_HEAD_RESP_AGE,               <<"Age">>).
-define(HTTP_HEAD_RESP_CACHE_CTRL,        <<"Cache-Control">>).
-define(HTTP_HEAD_RESP_CONTENT_LENGTH,    <<"Content-Length">>).
-define(HTTP_HEAD_RESP_CONTENT_MD5,       <<"Content-MD5">>).
-define(HTTP_HEAD_RESP_CONTENT_TYPE,      <<"Content-Type">>).
-define(HTTP_HEAD_RESP_ETAG,              <<"ETag">>).
-define(HTTP_HEAD_RESP_IF_MODIFIED_SINCE, <<"If-Modified-Since">>).
-define(HTTP_HEAD_RESP_LAST_MODIFIED,     <<"Last-Modified">>).

-define(HTTP_HEAD_X_AMZ_META_DIRECTIVE,         <<"x-amz-metadata-directive">>).
-define(HTTP_HEAD_X_AMZ_COPY_SOURCE,            <<"x-amz-copy-source">>).
-define(HTTP_HEAD_X_AMZ_ID_2,                   <<"x-amz-id-2">>).
-define(HTTP_HEAD_X_AMZ_REQ_ID,                 <<"x-amz-request-id">>).
-define(HTTP_HEAD_X_AMZ_META_DIRECTIVE_COPY,    <<"COPY">>).
-define(HTTP_HEAD_X_AMZ_META_DIRECTIVE_REPLACE, <<"REPLACE">>).
-define(HTTP_HEAD_X_FROM_CACHE,                 <<"x-from-cache">>).

-define(HTTP_CTYPE_OCTET_STREAM, <<"application/octet-stream">>).
-define(HTTP_CTYPE_XML,          <<"application/xml">>).

-define(HTTP_QS_BIN_ACL,         <<"acl">>).
-define(HTTP_QS_BIN_UPLOADS,     <<"uploads">>).
-define(HTTP_QS_BIN_UPLOAD_ID,   <<"uploadId">>).
-define(HTTP_QS_BIN_PART_NUMBER, <<"partNumber">>).
-define(HTTP_QS_BIN_MARKER,      <<"marker">>).
-define(HTTP_QS_BIN_MAXKEYS,     <<"max-keys">>).

-define(HTTP_ST_OK,                  200).
-define(HTTP_ST_NO_CONTENT,          204).
-define(HTTP_ST_PARTIAL_CONTENT,     206).
-define(HTTP_ST_NOT_MODIFIED,        304).
-define(HTTP_ST_BAD_REQ,             400).
-define(HTTP_ST_FORBIDDEN,           403).
-define(HTTP_ST_NOT_FOUND,           404).
-define(HTTP_ST_BAD_RANGE,           416).
-define(HTTP_ST_INTERNAL_ERROR,      500).
-define(HTTP_ST_SERVICE_UNAVAILABLE, 503).
-define(HTTP_ST_GATEWAY_TIMEOUT,     504).

-define(CACHE_HTTP,  'http').
-define(CACHE_INNER, 'inner').
-type(cache_method() :: ?CACHE_HTTP | ?CACHE_INNER).


-define(HTTP_HANDLER_S3,    'leo_gateway_s3_api').
-define(HTTP_HANDLER_SWIFT, 'leo_gateway_swift_api').
-define(HTTP_HANDLER_REST,  'leo_gateway_rest_api').
-define(HTTP_HANDLER_EMBED, 'leo_gateway_embed').

-type(http_handler() :: ?HTTP_HANDLER_S3 | ?HTTP_HANDLER_SWIFT | ?HTTP_HANDLER_REST).

-define(convert_to_handler(_V), case _V of
                                    'rest'  -> ?HTTP_HANDLER_REST;
                                    'swift' -> ?HTTP_HANDLER_SWIFT;
                                    's3'    -> ?HTTP_HANDLER_S3;
                                    'embed' -> ?HTTP_HANDLER_EMBED;
                                    _       -> ?HTTP_HANDLER_S3
                                end).

%% Default values
-define(DEF_HTTTP_HANDLER,            's3').
-define(DEF_HTTP_PORT,                8080).
-define(DEF_HTTP_SSL_PORT,            8443).
-define(DEF_HTTP_SSL_C_FILE,          "./server_cert.pem").
-define(DEF_HTTP_SSL_K_FILE,          "./server_key.pem").
-define(DEF_HTTP_NUM_OF_ACCEPTORS,    32).
-define(DEF_HTTP_CACHE,               false).
-define(DEF_HTTP_MAX_KEEPALIVE,       1024).
-define(DEF_CACHE_WORKERS,            64).
-define(DEF_CACHE_RAM_CAPACITY,       64000000).
-define(DEF_CACHE_DISC_CAPACITY,      64000000).
-define(DEF_CACHE_DISC_THRESHOLD_LEN, 1000000).
-define(DEF_CACHE_DISC_DIR_DATA,      "./cache/data").
-define(DEF_CACHE_DISC_DIR_JOURNAL,   "./cache/journal").
-define(DEF_CACHE_EXPIRE,             300).
-define(DEF_CACHE_MAX_CONTENT_LEN,    1000000).
-define(DEF_LOBJ_MAX_CHUNKED_OBJS,    1000).
-define(DEF_LOBJ_MAX_LEN_FOR_OBJ,     524288000).
-define(DEF_LOBJ_CHUNK_OBJ_LEN,       5242880).
-define(DEF_LOBJ_THRESHOLD_OBJ_LEN,   5767168).


%% Macros
-define(reply_ok(_H,_R),                 cowboy_req:reply(?HTTP_ST_OK,              _H,_R)).    %% 200
-define(reply_ok(_H,_B,_R),              cowboy_req:reply(?HTTP_ST_OK,              _H,_B,_R)). %% 200 with body
-define(reply_no_content(_H,_R),         cowboy_req:reply(?HTTP_ST_NO_CONTENT,      _H,_R)).    %% 204
-define(reply_partial_content(_H,_R),    cowboy_req:reply(?HTTP_ST_PARTIAL_CONTENT, _H,_R)).    %% 206
-define(reply_partial_content(_H,_B,_R), cowboy_req:reply(?HTTP_ST_PARTIAL_CONTENT, _H,_B,_R)). %% 206 with body
-define(reply_not_modified(_H,_R),       cowboy_req:reply(?HTTP_ST_NOT_MODIFIED,    _H,_R)). %% 304
-define(reply_bad_request(_H,_R),        cowboy_req:reply(?HTTP_ST_BAD_REQ,         _H,_R)). %% 400
-define(reply_forbidden(_H,_R),          cowboy_req:reply(?HTTP_ST_FORBIDDEN,       _H,_R)). %% 403
-define(reply_not_found(_H,_R),          cowboy_req:reply(?HTTP_ST_NOT_FOUND,       _H,_R)). %% 404
-define(reply_bad_range(_H,_R),          cowboy_req:reply(?HTTP_ST_BAD_RANGE,       _H,_R)). %% 416
-define(reply_internal_error(_H,_R),     cowboy_req:reply(?HTTP_ST_INTERNAL_ERROR,  _H,_R)). %% 500
-define(reply_timeout(_H,_R),            cowboy_req:reply(?HTTP_ST_GATEWAY_TIMEOUT, _H,_R)). %% 504


-define(http_header(_R, _K),   case cowboy_req:header(_K, _R) of
                                   {undefined, _} -> ?BIN_EMPTY;
                                   {Bin, _}       -> Bin
                               end).
-define(http_etag(_E),         lists:append(["\"", leo_hex:integer_to_hex(_E,32), "\""])).
-define(http_date(_D),         leo_http:rfc1123_date(_D)).
-define(httP_cache_ctl(_C),    lists:append(["max-age=",integer_to_list(_C)])).
-define(http_content_type(_H), case lists:keyfind(?HTTP_HEAD_CONTENT_TYPE,1,_H) of
                                   false     -> ?HTTP_CTYPE_OCTET_STREAM;
                                   {_, Val} -> Val
                               end).


%% S3 Response XML
-define(XML_BUCKET_LIST,
        lists:append(["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                      "<ListAllMyBucketsResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01\">",
                      "<Owner>",
                      "  <ID>LeoFS</ID>",
                      "  <DisplayName>webfile</DisplayName>",
                      "</Owner>",
                      "<Buckets>",
                      "~s",
                      "</Buckets></ListAllMyBucketsResult>"])).

-define(XML_OBJ_LIST,
        lists:append(["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                      "<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">",
                      "  <Name>standalone</Name>",
                      "  <Prefix>~s</Prefix>",
                      "  <Marker></Marker>",
                      "  <NextMarker>~s</NextMarker>",
                      "  <MaxKeys>~s</MaxKeys>",
                      "  <Delimiter>/</Delimiter>",
                      "  <IsTruncated>~s</IsTruncated>",
                      "~s",
                      "</ListBucketResult>"])).

-define(XML_COPY_OBJ_RESULT,
        lists:append(["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                      "<CopyObjectResult>",
                      "  <LastModified>~s</LastModified>",
                      "  <ETag>\"~s\"</ETag>",
                      "</CopyObjectResult>"])).

-define(XML_UPLOAD_INITIATION,
        lists:append(["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                      "<InitiateMultipartUploadResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">"
                      "  <Bucket>~s</Bucket>"
                      "  <Key>~s</Key>"
                      "  <UploadId>~s</UploadId>"
                      "</InitiateMultipartUploadResult>"])).

-define(XML_UPLOAD_COMPLETION,
        lists:append(["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                      "<CompleteMultipartUploadResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">",
                      "  <Location>http://Example-Bucket.s3.amazonaws.com/Example-Object</Location>",
                      "  <Bucket>~s</Bucket>",
                      "  <Key>~s</Key>",
                      "  <ETag>\"~s\"</ETag>",
                      "</CompleteMultipartUploadResult>"])).


%% Records
-record(http_options, {
          %% for basic
          handler                      :: http_handler(), %% http-handler
          port = 0                     :: pos_integer(),  %% http port number
          ssl_port = 0                 :: pos_integer(),  %% ssl port number
          ssl_certfile = []            :: string(),       %% ssl cert file name
          ssl_keyfile = []             :: string(),       %% ssk key file name
          num_of_acceptors = 0         :: pos_integer(),  %% # of acceptors (http server's workers)
          max_keepalive = 0            :: pos_integer(),  %% # of request per processes
          %% for cache
          cache_method                 :: cache_method(), %% cahce method: [http | inner]
          cache_workers = 0            :: pos_integer(),  %% number of chache-fun's workers
          cache_ram_capacity = 0       :: pos_integer(),  %% cache size (RAM)
          cache_disc_capacity = 0      :: pos_integer(),  %% cache size (Disc)
          cache_disc_threshold_len = 0 :: pos_integer(),  %% cache disc threshold length (Disc)
          cache_disc_dir_data = []     :: string(),       %% cache-directory for data    (Disc)
          cache_disc_dir_journal = []  :: string(),       %% cache-directory for journal (Disc)
          cache_expire = 0             :: pos_integer(),  %% cache expire time (sec)
          cache_max_content_len = 0    :: pos_integer(),  %% cache max content length (byte)
          cachable_content_type = []   :: list(),         %% cachable content types
          cachable_path_pattern = []   :: list(),         %% cachable path patterns
          %% for large-object
          max_chunked_objs = 0         :: pos_integer(),  %% max chunked objects
          max_len_for_obj = 0          :: pos_integer(),  %% max length a object (byte)
          chunked_obj_len = 0          :: pos_integer(),  %% chunked object length for large object (byte)
          threshold_obj_len = 0        :: pos_integer()   %% threshold object length for large object (byte)
         }).

-record(req_params, {
          %% basic info
          handler                    :: http_handler(), %% http-handler
          path = <<>>                :: binary(),       %% path (uri)
          bucket = <<>>              :: binary(),       %% bucket (for s3-api)
          access_key_id = []         :: string(),       %% s3's access-key-id
          token_length = 0           :: pos_integer(),  %% length of tokened path
          min_layers = 0             :: pos_integer(),  %% acceptable # of min layers
          max_layers = 0             :: pos_integer(),  %% acceptable # of max layers
          qs_prefix = []             :: string(),       %% query string
          range_header               :: string(),       %% range header
          has_inner_cache = false    :: boolean(),      %% has inner-cache?
          is_cached = false          :: boolean(),      %% is cached?
          is_dir = false             :: boolean(),      %% is directory?
          %% for large-object
          is_upload = false          :: boolean(),      %% is upload operation? (for multipart upload)
          upload_id = <<>>           :: binary(),       %% upload id for multipart upload
          upload_part_num = 0        :: pos_integer(),  %% upload part number for multipart upload
          max_chunked_objs = 0       :: pos_integer(),  %% max chunked objects
          max_len_for_multipart = 0  :: pos_integer(),  %% max length a multipart object (byte)
          max_len_for_obj = 0        :: pos_integer(),  %% max length a object (byte)
          chunked_obj_len = 0        :: pos_integer(),  %% chunked object length for large-object (byte)
          threshold_obj_len = 0      :: pos_integer()   %% threshold object length for large-object (byte)
         }).

-record(cache, {
          etag         = 0    :: pos_integer(), %% actual value is checksum
          mtime        = 0    :: pos_integer(), %% gregorian_seconds
          content_type = []   :: string(),      %% from a Content-Type header
          body         = <<>> :: binary(),      %% body (value),
          size         = 0    :: pos_integer(), %% body size
          file_path    = ""   :: file:name_all()%% file path when this cache is stored on disk
         }).

-record(cache_condition, {
          expire          = 0  :: integer(), %% specified per sec
          max_content_len = 0  :: integer(), %% No cache if Content-Length of a response header was &gt this
          content_types   = [] :: list(),    %% like ["image/png", "image/gif", "image/jpeg"]
          path_patterns   = [] :: list()     %% compiled regular expressions
         }).

