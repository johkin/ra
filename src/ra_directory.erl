-module(ra_directory).

-export([
         init/1,
         deinit/0,
         register_name/3,
         unregister_name/1,
         where_is/1,
         name_of/1,
         uid_of/1,
         send/2,
         overview/0
         ]).

-export_type([
              ]).

-include("ra.hrl").

-define(REVERSE_TBL, ra_directory_reverse).

% registry for a ra node's locally unique name

-spec init(file:filename()) -> ok.
init(Dir) ->
    _ = ets:new(?MODULE, [named_table,
                          public,
                          {read_concurrency, true},
                          {write_concurrency, true}
                         ]),
    Dets = filename:join(Dir, "names.dets"),
    ok = filelib:ensure_dir(Dets),
    {ok, ?REVERSE_TBL} = dets:open_file(?REVERSE_TBL,
                                        [{file, Dets},
                                         {auto_save, 500},
                                         {access, read_write}]),
    ok.

-spec deinit() -> ok.
deinit() ->
    _ = ets:delete(?MODULE),
    _ = dets:close(?REVERSE_TBL),
    ok.

-spec register_name(ra_uid(), pid(), atom()) -> yes | no.
register_name(UId, Pid, RaNodeName) ->
    true = ets:insert(?MODULE, {UId, Pid, RaNodeName}),
    ok = dets:insert(?REVERSE_TBL, {RaNodeName, UId}),
    yes.

-spec unregister_name(ra_uid()) -> ra_uid().
unregister_name(UId) ->
    case ets:take(?MODULE, UId) of
        [{_, _, NodeName}] ->
            ets:take(?MODULE, UId),
            ok = dets:delete(?REVERSE_TBL, NodeName),
            UId;
        [] ->
            UId
    end.

-spec where_is(ra_uid() | atom()) -> pid() | undefined.
where_is(NodeName) when is_atom(NodeName) ->
    case dets:lookup(?REVERSE_TBL, NodeName) of
        [] -> undefined;
        [{_, UId}] ->
            where_is(UId)
    end;
where_is(UId) when is_binary(UId) ->
    case ets:lookup(?MODULE, UId) of
        [{_, Pid, _}] -> Pid;
        [] -> undefined
    end.

-spec name_of(ra_uid()) -> atom().
name_of(UId) ->
    case ets:lookup(?MODULE, UId) of
        [{_UId, _Pid, Node}] -> Node;
        [] -> undefined
    end.

uid_of(NodeName) when is_atom(NodeName) ->
    case dets:lookup(?REVERSE_TBL, NodeName) of
        [] -> undefined;
        [{_, UId}] ->
            UId
    end.

-spec send(ra_uid() | atom(), term()) -> pid().
send(UIdOrName, Msg) ->
    case where_is(UIdOrName) of
        undefined ->
            exit({badarg, {UIdOrName, Msg}});
        Pid ->
            _ = erlang:send(Pid, Msg),
            Pid
    end.

overview() ->
    Dir = ets:tab2list(ra_directory),
    States = maps:from_list(ets:tab2list(ra_state)),
    Snaps = maps:from_list(ets:tab2list(ra_log_snapshot_state)),
    lists:foldl(fun ({UId, Pid, Node}, Acc) ->
                        Acc#{Node =>
                             #{uid => UId,
                               pid => Pid,
                               state => maps:get(Node, States, undefined),
                               snapshot_state => maps:get(UId, Snaps,
                                                          undefined)}}
                end, #{}, Dir).
