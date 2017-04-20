%% Feel free to use, reuse and abuse the code in this file.

%% @private
-module(hello_world_app).
-behaviour(application).

%% API.
-export([start/2]).
-export([stop/1]).

%% API.

start(_Type, _Args) ->
	Dispatch = cowboy_router:compile([
                                      {'_', [
                                             {"/",             cowboy_static, {priv_file, hello_world, "index.html", [{mimetypes, cow_mimetypes, all}]}},
                                             {"/js/[...]",     cowboy_static, {priv_dir,  hello_world, "js",         [{mimetypes, cow_mimetypes, all}]}},
                                             {"/css/[...]",    cowboy_static, {priv_dir,  hello_world, "css",        [{mimetypes, cow_mimetypes, all}]}},
                                             {"/rest", handler_rest, []}
                                            ]}
                                     ]),
	{ok, _} = cowboy:start_clear(http, 100, [{port, 8080}], #{
                                              env => #{dispatch => Dispatch}
                                             }),
	hello_world_sup:start_link().

stop(_State) ->
	ok.
