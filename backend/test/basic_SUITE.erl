-module(basic_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([test1/1, test2/1]).
%% -compile(export_all).

all() -> [test1, test2].

test1(_Config) ->
    1 =:= 1.

test2(_Config) ->
    2 * 2 =:= 4.

