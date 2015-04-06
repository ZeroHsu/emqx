%%%-----------------------------------------------------------------------------
%%% @Copyright (C) 2012-2015, Feng Lee <feng@emqtt.io>
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in all
%%% copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%%% SOFTWARE.
%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd ACL.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_acl).

-author('feng@emqtt.io').

-include("emqttd.hrl").

-behaviour(gen_server).

-define(SERVER, ?MODULE).

%% API Function Exports
-export([start_link/1, check/3, reload/0, register_mod/1, unregister_mod/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(ACL_TABLE, mqtt_acl).

%%%=============================================================================
%%% ACL behavihour
%%%=============================================================================

-ifdef(use_specs).

-callback check_acl(PubSub, User, Topic) -> {ok, allow | deny} | ignore | {error, any()} when
    PubSub   :: publish | subscribe,
    User     :: mqtt_user(),
    Topic    :: binary().

-callback reload_acl() -> ok | {error, any()}.

-else.

-export([behaviour_info/1]).

behaviour_info(callbacks) ->
        [{check_acl, 3}, {reload_acl, 0}, {description, 0}];
behaviour_info(_Other) ->
        undefined.

-endif.

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% Start ACL Server.
%%
%% @end
%%------------------------------------------------------------------------------
-spec start_link(AclOpts) -> {ok, pid()} | ignore | {error, any()} when
    AclOpts     :: [{file, list()}].
start_link(AclOpts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [AclOpts], []).

%%------------------------------------------------------------------------------
%% @doc
%% Check ACL.
%%
%% @end
%%------------------------------------------------------------------------------
-spec check(PubSub, User, Topic) -> {ok, allow | deny} | {error, any()} when
      PubSub :: publish | subscribe,
      User   :: mqtt_user(),
      Topic  :: binary().
check(PubSub, User, Topic) when PubSub =:= publish orelse PubSub =:= subscribe ->
    case ets:lookup(?ACL_TABLE, acl_mods) of
        [] -> {error, "No ACL mods!"};
        [{_, Mods}] -> check(PubSub, User, Topic, Mods)
    end.

check(_PubSub, _User, _Topic, []) ->
    {error, "All ACL mods ignored!"};

check(PubSub, User, Topic, [Mod|Mods]) ->
    case Mod:check_acl(PubSub, User, Topic) of
        {ok, AllowDeny} -> {ok, AllowDeny};
        ignore -> check(PubSub, User, Topic, Mods)
    end.

%%------------------------------------------------------------------------------
%% @doc
%% Reload ACL.
%%
%% @end
%%------------------------------------------------------------------------------
reload() ->
    case ets:lookup(?ACL_TABLE, acl_mods) of
        [] -> {error, "No ACL mod!"};
        [{_, Mods}] -> [M:reload() || M <- Mods]
    end.

%%------------------------------------------------------------------------------
%% @doc
%% Register ACL Module.
%%
%% @end
%%------------------------------------------------------------------------------
-spec register_mod(Mod :: atom()) -> ok | {error, any()}.
register_mod(Mod) ->
    gen_server:call(?SERVER, {register_mod, Mod}).

%%------------------------------------------------------------------------------
%% @doc
%% Unregister ACL Module.
%%
%% @end
%%------------------------------------------------------------------------------
-spec unregister_mod(Mod :: atom()) -> ok | {error, any()}.
unregister_mod(Mod) ->
    gen_server:call(?SERVER, {unregister_mod, Mod}).

%%%=============================================================================
%%% gen_server callbacks.
%%%=============================================================================
init([_AclOpts]) ->
    ets:new(?ACL_TABLE, [set, protected, named_table]),
    {ok, state}.

handle_call({register_mod, Mod}, _From, State) ->
    Mods = acl_mods(),
    case lists:member(Mod, Mods) of
        true ->
            {reply, {error, registered}, State};
        false ->
            ets:insert(?ACL_TABLE, {acl_mods, [Mod | Mods]}),
            {reply, ok, State}
    end;

handle_call({unregister_mod, Mod}, _From, State) ->
    Mods = acl_mods(),
    case lists:member(Mod, Mods) of
        true ->
            ets:insert(?ACL_TABLE, lists:delete(Mod, Mods)),
            {reply, ok, State};
        false -> 
            {reply, {error, not_found}, State}
    end;

handle_call(Req, _From, State) ->
    lager:error("Bad Request: ~p", [Req]),
    {reply, {error, badreq}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================
acl_mods() ->
    case ets:lookup(?ACL_TABLE, acl_mods) of
        [] -> [];
        [{_, Mods}] -> Mods
    end.

