%%%
%%% Copyright 2017 RBKmoney
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%

-module(mg_events_sink_SUITE).
-include_lib("common_test/include/ct.hrl").

%% tests descriptions
-export([all           /0]).
-export([groups        /0]).
-export([init_per_suite/1]).
-export([end_per_suite /1]).

%% tests
-export([add_events               /1]).
-export([get_history              /1]).
-export([get_unexisted_event      /1]).
-export([idempotent_add_get_events/1]).

%% Pulse
-export([handle_beat/2]).

%%
%% tests descriptions
%%
-type group_name() :: atom().
-type test_name () :: atom().
-type config    () :: [{atom(), _}].

-spec all() ->
    [test_name()].
all() ->
    [
        {group, main}
    ].

-spec groups() ->
    [{group_name(), list(_), test_name()}].
groups() ->
    [
        {main, [sequence], [
            add_events,
            get_history,
            % TODO починить
            % get_unexisted_event,
            idempotent_add_get_events
        ]}
    ].

%%
%% starting/stopping
%%
-spec init_per_suite(config()) ->
    config().
init_per_suite(C) ->
    % dbg:tracer(), dbg:p(all, c),
    % dbg:tpl({mg_events_sink, '_', '_'}, x),
    Apps = genlib_app:start_application(mg),
    Pid = start_event_sink(event_sink_options()),
    true = erlang:unlink(Pid),
    {Events, _} = mg_events:generate_events_with_range([{#{}, Body} || Body <- [1, 2, 3]], undefined),
    [{apps, Apps}, {pid, Pid}, {events, Events}| C].

-spec end_per_suite(config()) ->
    ok.
end_per_suite(C) ->
    true = erlang:exit(?config(pid, C), kill),
    [application:stop(App) || App <- ?config(apps, C)].


%%
%% tests
%%
-define(ES_ID, <<"event_sink_id">>).
-define(SOURCE_NS, <<"source_ns">>).
-define(SOURCE_ID, <<"source_id">>).

-spec add_events(config()) ->
    _.
add_events(C) ->
    ok = mg_events_sink:add_events(event_sink_options(), ?ES_ID, ?SOURCE_NS, ?SOURCE_ID,
        ?config(events, C), null, mg_utils:default_deadline()).

-spec get_history(config()) ->
    _.
get_history(C) ->
    HRange = {undefined, undefined, forward},
    Events =
        [
            #{event => Event, source_ns => ?SOURCE_NS, source_id => ?SOURCE_ID}
            || Event <- ?config(events, C)
        ],
    PreparedEvents = lists:zip(lists:seq(1, erlang:length(?config(events, C))), Events),
    % _ = ct:pal("~p", [PreparedEvents]),
    PreparedEvents =
        [
            {ID, Body}
            ||
            #{id := ID, body := Body} <- mg_events_sink:get_history(event_sink_options(), ?ES_ID, HRange)
        ],
    ok.

-spec get_unexisted_event(config()) ->
    _.
get_unexisted_event(_C) ->
    [] = mg_events_sink:get_history(event_sink_options(), ?ES_ID, {42, undefined, forward}).

-spec idempotent_add_get_events(config()) ->
    _.
idempotent_add_get_events(C) ->
    ok = add_events(C),
    ok = get_history(C).

%%
%% utils
%%
-spec start_event_sink(mg_events_sink:options()) ->
    pid().
start_event_sink(Options) ->
    mg_utils:throw_if_error(
        mg_utils_supervisor_wrapper:start_link(
            #{strategy => one_for_all},
            [mg_events_sink:child_spec(Options, event_sink)]
        )
    ).

-spec event_sink_options() ->
    mg_events_sink:options().
event_sink_options() ->
    #{
        namespace              => ?ES_ID,
        storage                => mg_storage_memory,
        pulse                  => ?MODULE,
        duplicate_search_batch => 1000,
        events_storage         => mg_storage_memory
    }.

-spec handle_beat(_, mg_pulse:beat()) ->
    ok.
handle_beat(_, Beat) ->
    ct:pal("~p", [Beat]).
