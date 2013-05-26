%%% -*- coding: utf-8; Mode: erlang; tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*-
%%% ex: set softtabstop=4 tabstop=4 shiftwidth=4 expandtab fileencoding=utf-8:
%%%
%%%------------------------------------------------------------------------
%%% @doc
%%% ==CloudI External Service==
%%% Erlang process which provides the connection to a thread in an
%%% external service.
%%% @end
%%%
%%% BSD LICENSE
%%% 
%%% Copyright (c) 2011-2013, Michael Truog <mjtruog at gmail dot com>
%%% All rights reserved.
%%% 
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%% 
%%%     * Redistributions of source code must retain the above copyright
%%%       notice, this list of conditions and the following disclaimer.
%%%     * Redistributions in binary form must reproduce the above copyright
%%%       notice, this list of conditions and the following disclaimer in
%%%       the documentation and/or other materials provided with the
%%%       distribution.
%%%     * All advertising materials mentioning features or use of this
%%%       software must display the following acknowledgment:
%%%         This product includes software developed by Michael Truog
%%%     * The name of the author may not be used to endorse or promote
%%%       products derived from this software without specific prior
%%%       written permission
%%% 
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
%%% CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
%%% INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
%%% OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
%%% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
%%% CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%%% SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
%%% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
%%% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
%%% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
%%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
%%% NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
%%% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
%%% DAMAGE.
%%%
%%% @author Michael Truog <mjtruog [at] gmail (dot) com>
%%% @copyright 2011-2013 Michael Truog
%%% @version 1.2.2 {@date} {@time}
%%%------------------------------------------------------------------------

-module(cloudi_services_external).
-author('mjtruog [at] gmail (dot) com').

-behaviour(gen_fsm).

%% external interface
-export([start_link/12, port/1]).

%% gen_fsm callbacks
-export([init/1, handle_event/3,
         handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% FSM States
-export(['CONNECT'/2,
         'HANDLE'/2]).

-include("cloudi_configuration.hrl").
-include("cloudi_logger.hrl").
-include("cloudi_constants.hrl").

% message type enumeration
-define(MESSAGE_INIT,            1).
-define(MESSAGE_SEND_ASYNC,      2).
-define(MESSAGE_SEND_SYNC,       3).
-define(MESSAGE_RECV_ASYNC,      4).
-define(MESSAGE_RETURN_ASYNC,    5).
-define(MESSAGE_RETURN_SYNC,     6).
-define(MESSAGE_RETURNS_ASYNC,   7).
-define(MESSAGE_KEEPALIVE,       8).

-record(state,
    {
        % common elements for cloudi_services_common.hrl
        dispatcher,                    % self()
        send_timeouts = dict:new(),    % tracking for send timeouts
        recv_timeouts = dict:new(),    % tracking for recv timeouts
        async_responses = dict:new(),  % tracking for async requests
        queue_requests = true,         % is the external process busy?
        queued = cloudi_x_pqueue4:new(),        % queued incoming requests
        % unique state elements
        protocol,                      % tcp, udp, or local
        port,                          % port number used
        incoming_port,                 % udp incoming port
        listener,                      % tcp listener
        acceptor,                      % tcp acceptor
        socket_path,                   % local socket filesystem path
        socket_options,                % common socket options
        socket,                        % data socket
        prefix,                        % subscribe/unsubscribe name prefix
        timeout_async,                 % default timeout for send_async
        timeout_sync,                  % default timeout for send_sync
        os_pid = undefined,            % os_pid reported by the socket
        keepalive = undefined,         % stores if a keepalive succeeded
        init_timeout,                  % init timeout handler
        uuid_generator,                % transaction id generator
        dest_refresh,                  % immediate_closest | lazy_closest |
                                       % immediate_furthest | lazy_furthest |
                                       % immediate_random | lazy_random |
                                       % immediate_local | lazy_local |
                                       % immediate_remote | lazy_remote |
                                       % immediate_newest | lazy_newest |
                                       % immediate_oldest | lazy_oldest,
                                       % destination pid refresh
        cpg_data = cloudi_x_cpg_data:get_empty_groups(), % dest_refresh lazy
        dest_deny,                     % denied from sending to a destination
        dest_allow,                    % allowed to send to a destination
        options                        % #config_service_options{}
    }).

% unused, but necessary for cloudi_services_common.hrl
-record(state_duo,
    {
        % common elements for cloudi_services_common.hrl
        duo_mode_pid,                  % unused
        unused_element1,               % unused
        recv_timeouts,                 % unused
        unused_element2,               % unused
        queue_requests,                % unused
        queued                         % unused
        % unique state elements
    }).

-include("cloudi_services_common.hrl").

%%%------------------------------------------------------------------------
%%% External interface functions
%%%------------------------------------------------------------------------

start_link(Protocol, SocketPath, ThreadIndex, BufferSize, Timeout,
           Prefix, TimeoutAsync, TimeoutSync,
           DestRefresh, DestDeny, DestAllow, ConfigOptions)
    when is_atom(Protocol), is_list(SocketPath), is_integer(ThreadIndex),
         is_integer(BufferSize), is_integer(Timeout), is_list(Prefix),
         is_integer(TimeoutAsync), is_integer(TimeoutSync),
         is_record(ConfigOptions, config_service_options) ->
    true = (Protocol =:= tcp) orelse
           (Protocol =:= udp) orelse
           (Protocol =:= local),
    true = (DestRefresh =:= immediate_closest) orelse
           (DestRefresh =:= lazy_closest) orelse
           (DestRefresh =:= immediate_furthest) orelse
           (DestRefresh =:= lazy_furthest) orelse
           (DestRefresh =:= immediate_random) orelse
           (DestRefresh =:= lazy_random) orelse
           (DestRefresh =:= immediate_local) orelse
           (DestRefresh =:= lazy_local) orelse
           (DestRefresh =:= immediate_remote) orelse
           (DestRefresh =:= lazy_remote) orelse
           (DestRefresh =:= immediate_newest) orelse
           (DestRefresh =:= lazy_newest) orelse
           (DestRefresh =:= immediate_oldest) orelse
           (DestRefresh =:= lazy_oldest) orelse
           (DestRefresh =:= none),
    gen_fsm:start_link(?MODULE,
                       [Protocol, SocketPath, ThreadIndex, BufferSize, Timeout,
                        Prefix, TimeoutAsync, TimeoutSync, DestRefresh,
                        DestDeny, DestAllow, ConfigOptions], []).

port(Process) when is_pid(Process) ->
    gen_fsm:sync_send_all_state_event(Process, port).

%%%------------------------------------------------------------------------
%%% Callback functions from gen_fsm
%%%------------------------------------------------------------------------

init([Protocol, SocketPath, ThreadIndex, BufferSize, Timeout,
      Prefix, TimeoutAsync, TimeoutSync,
      DestRefresh, DestDeny, DestAllow, ConfigOptions])
    when Protocol =:= tcp;
         Protocol =:= udp;
         Protocol =:= local ->
    Dispatcher = self(),
    InitTimeout = erlang:send_after(Timeout, Dispatcher,
                                    'cloudi_service_init_timeout'),
    process_flag(trap_exit, true),
    case socket_open(Protocol, SocketPath, ThreadIndex, BufferSize) of
        {ok, State} ->
            cloudi_x_quickrand:seed(),
            destination_refresh_first(DestRefresh, ConfigOptions),
            {ok, 'CONNECT',
             State#state{dispatcher = Dispatcher,
                         prefix = Prefix,
                         timeout_async = TimeoutAsync,
                         timeout_sync = TimeoutSync,
                         init_timeout = InitTimeout,
                         uuid_generator = cloudi_x_uuid:new(Dispatcher),
                         dest_refresh = DestRefresh,
                         dest_deny = DestDeny,
                         dest_allow = DestAllow,
                         options = ConfigOptions}};
        {error, Reason} ->
            {stop, Reason}
    end.

% incoming messages (from the port socket)

'CONNECT'({'pid', OsPid}, State) ->
    % forked process has connected before CloudI API initialization
    ?LOG_INFO("OS pid ~w connected", [OsPid]),
    {next_state, 'CONNECT', State#state{os_pid = OsPid}};

'CONNECT'('init', #state{dispatcher = Dispatcher,
                         protocol = Protocol,
                         prefix = Prefix,
                         timeout_async = TimeoutAsync,
                         timeout_sync = TimeoutSync,
                         options = ConfigOptions} = State) ->
    % first message within the CloudI API received during
    % the object construction or init API function
    PriorityDefault =
        ConfigOptions#config_service_options.priority_default,
    RequestTimeoutAdjustment =
        ConfigOptions#config_service_options.request_timeout_adjustment,
    send('init_out'(Prefix, TimeoutAsync, TimeoutSync,
                    PriorityDefault, RequestTimeoutAdjustment),
         State),
    if
        Protocol =:= udp ->
            send('keepalive_out'(), State),
            erlang:send_after(?KEEPALIVE_UDP, Dispatcher, keepalive_udp);
        true ->
            ok
    end,
    {next_state, 'HANDLE', State};

'CONNECT'(Request, State) ->
    {stop, {'CONNECT', undefined_message, Request}, State}.

'HANDLE'('polling', #state{init_timeout = InitTimeout} = State) ->
    % initialization is now complete because the CloudI API poll function
    % has been called for the first time (i.e., by the service code)
    erlang:cancel_timer(InitTimeout),
    {next_state, 'HANDLE',
     process_queue(State#state{init_timeout = undefined})};

'HANDLE'({'subscribe', Pattern},
         #state{dispatcher = Dispatcher,
                prefix = Prefix} = State) ->
    ok = cloudi_x_cpg:join(Prefix ++ Pattern, Dispatcher),
    {next_state, 'HANDLE', State};

'HANDLE'({'unsubscribe', Pattern},
         #state{dispatcher = Dispatcher,
                prefix = Prefix} = State) ->
    ok = cloudi_x_cpg:leave(Prefix ++ Pattern, Dispatcher),
    {next_state, 'HANDLE', State};

'HANDLE'({'send_async', Name, RequestInfo, Request, Timeout, Priority},
         #state{dest_deny = DestDeny,
                dest_allow = DestAllow} = State) ->
    case destination_allowed(Name, DestDeny, DestAllow) of
        true ->
            handle_send_async(Name, RequestInfo, Request,
                              Timeout, Priority, 'HANDLE', State);
        false ->
            send('return_async_out'(), State),
            {next_state, 'HANDLE', State}
    end;

'HANDLE'({'send_sync', Name, RequestInfo, Request, Timeout, Priority},
         #state{dest_deny = DestDeny,
                dest_allow = DestAllow} = State) ->
    case destination_allowed(Name, DestDeny, DestAllow) of
        true ->
            handle_send_sync(Name, RequestInfo, Request,
                             Timeout, Priority, 'HANDLE', State);
        false ->
            send('return_sync_out'(), State),
            {next_state, 'HANDLE', State}
    end;

'HANDLE'({'mcast_async', Name, RequestInfo, Request, Timeout, Priority},
         #state{dest_deny = DestDeny,
                dest_allow = DestAllow} = State) ->
    case destination_allowed(Name, DestDeny, DestAllow) of
        true ->
            handle_mcast_async(Name, RequestInfo, Request,
                               Timeout, Priority, 'HANDLE', State);
        false ->
            send('returns_async_out'(), State),
            {next_state, 'HANDLE', State}
    end;

'HANDLE'({'forward_async', Name, RequestInfo, Request,
          Timeout, Priority, TransId, Source},
         #state{dispatcher = Dispatcher,
                dest_refresh = DestRefresh,
                cpg_data = Groups,
                dest_deny = DestDeny,
                dest_allow = DestAllow} = State) ->
    case destination_allowed(Name, DestDeny, DestAllow) of
        true ->
            case destination_get(DestRefresh, Name, Source, Groups) of
                {error, _} when Timeout >= ?FORWARD_ASYNC_INTERVAL ->
                    erlang:send_after(?FORWARD_ASYNC_INTERVAL, Dispatcher,
                                      {'cloudi_service_forward_async_retry',
                                       Name, RequestInfo, Request,
                                       Timeout - ?FORWARD_ASYNC_INTERVAL,
                                       Priority, TransId, Source}),
                    ok;
                {error, _} ->
                    ok;
                {ok, NextPattern, NextPid} when Timeout >= ?FORWARD_DELTA ->
                    NextPid ! {'cloudi_service_send_async',
                               Name, NextPattern,
                               RequestInfo, Request,
                               Timeout - ?FORWARD_DELTA,
                               Priority, TransId, Source};
                _ ->
                    ok
            end;
        false ->
            ok
    end,
    {next_state, 'HANDLE', process_queue(State)};

'HANDLE'({'forward_sync', Name, RequestInfo, Request,
          Timeout, Priority, TransId, Source},
         #state{dispatcher = Dispatcher,
                dest_refresh = DestRefresh,
                cpg_data = Groups,
                dest_deny = DestDeny,
                dest_allow = DestAllow} = State) ->
    case destination_allowed(Name, DestDeny, DestAllow) of
        true ->
            case destination_get(DestRefresh, Name, Source, Groups) of
                {error, _} when Timeout >= ?FORWARD_SYNC_INTERVAL ->
                    erlang:send_after(?FORWARD_SYNC_INTERVAL, Dispatcher,
                                      {'cloudi_service_forward_sync_retry',
                                       Name, RequestInfo, Request,
                                       Timeout - ?FORWARD_SYNC_INTERVAL,
                                       Priority, TransId, Source}),
                    ok;
                {error, _} ->
                    ok;
                {ok, NextPattern, NextPid} when Timeout >= ?FORWARD_DELTA ->
                    NextPid ! {'cloudi_service_send_sync',
                               Name, NextPattern,
                               RequestInfo, Request,
                               Timeout - ?FORWARD_DELTA,
                               Priority, TransId, Source};
                _ ->
                    ok
            end;
        false ->
            ok
    end,
    {next_state, 'HANDLE', process_queue(State)};

'HANDLE'({'recv_async', Timeout, TransId, Consume},
         #state{dispatcher = Dispatcher,
                async_responses = AsyncResponses} = State) ->
    if
        TransId == <<0:128>> ->
            case dict:to_list(AsyncResponses) of
                [] when Timeout >= ?RECV_ASYNC_INTERVAL ->
                    erlang:send_after(?RECV_ASYNC_INTERVAL, Dispatcher,
                                      {'cloudi_service_recv_async_retry',
                                       Timeout - ?RECV_ASYNC_INTERVAL,
                                       TransId, Consume}),
                    {next_state, 'HANDLE', State};
                [] ->
                    send('recv_async_out'(timeout, TransId), State),
                    {next_state, 'HANDLE', State};
                L when Consume =:= true ->
                    TransIdPick = ?RECV_ASYNC_STRATEGY(L),
                    {ResponseInfo, Response} = dict:fetch(TransIdPick,
                                                          AsyncResponses),
                    send('recv_async_out'(ResponseInfo, Response, TransIdPick),
                         State),
                    {next_state, 'HANDLE', State#state{
                        async_responses = dict:erase(TransIdPick,
                                                     AsyncResponses)}};
                L when Consume =:= false ->
                    TransIdPick = ?RECV_ASYNC_STRATEGY(L),
                    {ResponseInfo, Response} = dict:fetch(TransIdPick,
                                                          AsyncResponses),
                    send('recv_async_out'(ResponseInfo, Response, TransIdPick),
                         State),
                    {next_state, 'HANDLE', State}
            end;
        true ->
            case dict:find(TransId, AsyncResponses) of
                error when Timeout >= ?RECV_ASYNC_INTERVAL ->
                    erlang:send_after(?RECV_ASYNC_INTERVAL, Dispatcher,
                                      {'cloudi_service_recv_async_retry',
                                       Timeout - ?RECV_ASYNC_INTERVAL,
                                       TransId, Consume}),
                    {next_state, 'HANDLE', State};
                error ->
                    send('recv_async_out'(timeout, TransId), State),
                    {next_state, 'HANDLE', State};
                {ok, {ResponseInfo, Response}} when Consume =:= true ->
                    send('recv_async_out'(ResponseInfo, Response, TransId),
                         State),
                    {next_state, 'HANDLE', State#state{
                        async_responses = dict:erase(TransId,
                                                     AsyncResponses)}};
                {ok, {ResponseInfo, Response}} when Consume =:= false ->
                    send('recv_async_out'(ResponseInfo, Response, TransId),
                         State),
                    {next_state, 'HANDLE', State}
            end
    end;

'HANDLE'({'return_async', Name, Pattern, ResponseInfo, Response,
          Timeout, TransId, Source},
         State) ->
    Source ! {'cloudi_service_return_async', Name, Pattern,
              ResponseInfo, Response,
              Timeout, TransId, Source},
    {next_state, 'HANDLE', process_queue(State)};

'HANDLE'({'return_sync', Name, Pattern, ResponseInfo, Response,
          Timeout, TransId, Source},
         State) ->
    Source ! {'cloudi_service_return_sync', Name, Pattern,
              ResponseInfo, Response,
              Timeout, TransId, Source},
    {next_state, 'HANDLE', process_queue(State)};

'HANDLE'('keepalive', State) ->
    {next_state, 'HANDLE', State#state{keepalive = received}};

'HANDLE'(Request, State) ->
    {stop, {'HANDLE', undefined_message, Request}, State}.

handle_sync_event(port, _, StateName, #state{port = Port} = State) ->
    {reply, Port, StateName, State};

handle_sync_event(Event, _From, StateName, State) ->
    ?LOG_WARN("Unknown event \"~p\"", [Event]),
    {stop, {StateName, undefined_event, Event}, State}.

handle_event(Event, StateName, State) ->
    ?LOG_WARN("Unknown event \"~p\"", [Event]),
    {stop, {StateName, undefined_event, Event}, State}.

handle_info({udp, Socket, _, Port, Data}, StateName,
            #state{protocol = udp,
                   incoming_port = Port,
                   socket = Socket} = State) ->
    inet:setopts(Socket, [{active, once}]),
    try ?MODULE:StateName(erlang:binary_to_term(Data, [safe]), State)
    catch
        error:badarg ->
            ?LOG_ERROR("Protocol Error ~p", [Data]),
            {stop, {error, protocol}, State}
    end;

handle_info({udp, Socket, _, Port, Data}, StateName,
            #state{protocol = udp,
                   socket = Socket} = State) ->
    inet:setopts(Socket, [{active, once}]),
    try ?MODULE:StateName(erlang:binary_to_term(Data, [safe]),
                          State#state{incoming_port = Port})
    catch
        error:badarg ->
            ?LOG_ERROR("Protocol Error ~p", [Data]),
            {stop, {error, protocol}, State}
    end;

handle_info(keepalive_udp, StateName,
            #state{dispatcher = Dispatcher,
                   keepalive = undefined,
                   socket = Socket} = State) ->
    Dispatcher ! {udp_closed, Socket},
    {next_state, StateName, State};

handle_info(keepalive_udp, StateName,
            #state{dispatcher = Dispatcher,
                   keepalive = received} = State) ->
    send('keepalive_out'(), State),
    erlang:send_after(?KEEPALIVE_UDP, Dispatcher, keepalive_udp),
    {next_state, StateName, State#state{keepalive = undefined}};

handle_info({udp_closed, Socket}, _,
            #state{protocol = udp,
                   socket = Socket} = State) ->
    {stop, normal, State};

handle_info({tcp, Socket, Data}, StateName,
            #state{protocol = Protocol,
                   socket = Socket} = State)
    when Protocol =:= tcp; Protocol =:= local ->
    inet:setopts(Socket, [{active, once}]),
    try ?MODULE:StateName(erlang:binary_to_term(Data, [safe]), State)
    catch
        error:badarg ->
            ?LOG_ERROR("Protocol Error ~p", [Data]),
            {stop, {error, protocol}, State}
    end;

handle_info({tcp_closed, Socket}, _,
            #state{protocol = Protocol,
                   socket = Socket} = State)
    when Protocol =:= tcp; Protocol =:= local ->
    {stop, normal, State};

handle_info({tcp_error, Socket, Reason}, _,
            #state{protocol = Protocol,
                   socket = Socket} = State)
    when Protocol =:= tcp; Protocol =:= local ->
    {stop, Reason, State};

handle_info({inet_async, Listener, Acceptor, {ok, Socket}}, StateName,
            #state{protocol = tcp,
                   listener = Listener,
                   acceptor = Acceptor,
                   socket_options = SocketOptions} = State) ->
    true = inet_db:register_socket(Socket, inet_tcp),
    ok = inet:setopts(Socket, [{active, once} | SocketOptions]),
    catch gen_tcp:close(Listener),
    {next_state, StateName, State#state{listener = undefined,
                                        acceptor = undefined,
                                        socket = Socket}};

handle_info({inet_async, Listener, Acceptor, {ok, Socket}}, StateName,
            #state{protocol = local,
                   listener = Listener,
                   acceptor = Acceptor,
                   socket_path = SocketPath,
                   socket_options = SocketOptions} = State) ->
    {ok, NewSocket} = local_accept(Listener, Socket,
                                   SocketPath, SocketOptions),
    catch gen_tcp:close(Listener),
    catch gen_tcp:close(Acceptor), % inet client to get Socket
    {next_state, StateName, State#state{listener = undefined,
                                        acceptor = undefined,
                                        socket = NewSocket}};

handle_info({inet_async, Listener, Acceptor, Error}, StateName,
            #state{protocol = Protocol,
                   listener = Listener,
                   acceptor = Acceptor} = State)
    when Protocol =:= tcp; Protocol =:= local ->
    {stop, {StateName, inet_async, Error}, State};

handle_info({cloudi_x_cpg_data, Groups}, StateName,
            #state{dest_refresh = DestRefresh,
                   options = ConfigOptions} = State) ->
    destination_refresh_start(DestRefresh, ConfigOptions),
    {next_state, StateName, State#state{cpg_data = Groups}};

handle_info('cloudi_service_init_timeout', _, State) ->
    {stop, timeout, State};

handle_info({'cloudi_service_send_async_retry', Name, RequestInfo, Request,
             Timeout, Priority}, StateName, State) ->
    handle_send_async(Name, RequestInfo, Request,
                      Timeout, Priority, StateName, State);

handle_info({'cloudi_service_send_sync_retry', Name, RequestInfo, Request,
             Timeout, Priority}, StateName, State) ->
    handle_send_sync(Name, RequestInfo, Request,
                     Timeout, Priority, StateName, State);

handle_info({'cloudi_service_mcast_async_retry', Name, RequestInfo, Request,
             Timeout, Priority}, StateName, State) ->
    handle_mcast_async(Name, RequestInfo, Request,
                       Timeout, Priority, StateName, State);

handle_info({'cloudi_service_forward_async_retry', Name, RequestInfo, Request,
             Timeout, Priority, TransId, Source}, StateName,
            #state{dispatcher = Dispatcher,
                   dest_refresh = DestRefresh,
                   cpg_data = Groups} = State) ->
    case destination_get(DestRefresh, Name, Source, Groups) of
        {error, _} when Timeout >= ?FORWARD_ASYNC_INTERVAL ->
            erlang:send_after(?FORWARD_ASYNC_INTERVAL, Dispatcher,
                              {'cloudi_service_forward_async_retry',
                               Name, RequestInfo, Request,
                               Timeout - ?FORWARD_ASYNC_INTERVAL,
                               Priority, TransId, Source}),
            ok;
        {error, _} ->
            ok;
        {ok, Pattern, NextPid} when Timeout >= ?FORWARD_DELTA ->
            NextPid ! {'cloudi_service_send_async', Name, Pattern,
                       RequestInfo, Request,
                       Timeout - ?FORWARD_DELTA,
                       Priority, TransId, Source};
        _ ->
            ok
    end,
    {next_state, StateName, State};

handle_info({'cloudi_service_forward_sync_retry', Name, RequestInfo, Request,
             Timeout, Priority, TransId, Source}, StateName,
            #state{dispatcher = Dispatcher,
                   dest_refresh = DestRefresh,
                   cpg_data = Groups} = State) ->
    case destination_get(DestRefresh, Name, Source, Groups) of
        {error, _} when Timeout >= ?FORWARD_SYNC_INTERVAL ->
            erlang:send_after(?FORWARD_SYNC_INTERVAL, Dispatcher,
                              {'cloudi_service_forward_sync_retry',
                               Name, RequestInfo, Request,
                               Timeout - ?FORWARD_SYNC_INTERVAL,
                               Priority, TransId, Source}),
            ok;
        {error, _} ->
            ok;
        {ok, Pattern, NextPid} when Timeout >= ?FORWARD_DELTA ->
            NextPid ! {'cloudi_service_send_sync', Name, Pattern,
                       RequestInfo, Request,
                       Timeout - ?FORWARD_DELTA,
                       Priority, TransId, Source};
        _ ->
            ok
    end,
    {next_state, StateName, State};

handle_info({'cloudi_service_recv_async_retry', Timeout, TransId, Consume},
            StateName, State) ->
    ?MODULE:StateName({'recv_async', Timeout, TransId, Consume}, State);

% incoming requests (from other Erlang pids that are CloudI services)

handle_info({'cloudi_service_send_async', _, _,
             RequestInfo, Request, Timeout, _, _, _}, StateName, State)
    when is_binary(RequestInfo) =:= false; is_binary(Request) =:= false;
         Timeout =:= 0 ->
    {next_state, StateName, State};

handle_info({'cloudi_service_send_async', Name, Pattern, RequestInfo, Request,
             Timeout, Priority, TransId, Pid}, StateName,
            #state{queue_requests = false} = State) ->
    send('send_async_out'(Name, Pattern, RequestInfo, Request,
                          Timeout, Priority, TransId, Pid), State),
    {next_state, StateName, State#state{queue_requests = true}};

handle_info({'cloudi_service_send_sync', _, _,
             RequestInfo, Request, Timeout, _, _, _}, StateName, State)
    when is_binary(RequestInfo) =:= false; is_binary(Request) =:= false;
         Timeout =:= 0 ->
    {next_state, StateName, State};

handle_info({'cloudi_service_send_sync', Name, Pattern, RequestInfo, Request,
             Timeout, Priority, TransId, Pid}, StateName,
            #state{queue_requests = false} = State) ->
    send('send_sync_out'(Name, Pattern, RequestInfo, Request,
                         Timeout, Priority, TransId, Pid), State),
    {next_state, StateName, State#state{queue_requests = true}};

handle_info({Type, _, _, _, _, Timeout, Priority, TransId, _} = T, StateName,
            #state{queue_requests = true,
                   queued = Queue,
                   options = ConfigOptions} = State)
    when Type =:= 'cloudi_service_send_async';
         Type =:= 'cloudi_service_send_sync' ->
    QueueLimit = ConfigOptions#config_service_options.queue_limit,
    QueueLimitOk = if
        QueueLimit /= undefined ->
            cloudi_x_pqueue4:len(Queue) < QueueLimit;
        true ->
            true
    end,
    if
        QueueLimitOk ->
            {next_state, StateName,
             recv_timeout_start(Timeout, Priority, TransId, T, State)};
        true ->
            {next_state, StateName, State}
    end;

handle_info({'cloudi_service_recv_timeout', Priority, TransId}, StateName,
            #state{recv_timeouts = RecvTimeouts,
                   queue_requests = QueueRequests,
                   queued = Queue} = State) ->
    NewQueue = if
        QueueRequests =:= true ->
            cloudi_x_pqueue4:filter(fun({_, _, _, _, _, _, _, Id, _}) ->
                Id /= TransId
            end, Priority, Queue);
        true ->
            Queue
    end,
    {next_state, StateName,
     State#state{recv_timeouts = dict:erase(TransId, RecvTimeouts),
                 queued = NewQueue}};

handle_info({'cloudi_service_return_async', _, _,
             ResponseInfo, Response, _, _, _}, StateName, State)
    when is_binary(ResponseInfo) =:= false; is_binary(Response) =:= false ->
    {next_state, StateName, State};

handle_info({'cloudi_service_return_async', _Name, _Pattern,
             ResponseInfo, Response, OldTimeout, TransId, Pid}, StateName,
            #state{dispatcher = Dispatcher,
                   send_timeouts = SendTimeouts,
                   options = ConfigOptions} = State) ->
    true = Pid =:= Dispatcher,
    case dict:find(TransId, SendTimeouts) of
        error ->
            % send_async timeout already occurred
            {next_state, StateName, State};
        {ok, {passive, Tref}} when Response == <<>> ->
            if
                ConfigOptions
                #config_service_options.response_timeout_adjustment ->
                    erlang:cancel_timer(Tref);
                true ->
                    ok
            end,
            {next_state, StateName,
             send_timeout_end(TransId, State)};
        {ok, {passive, Tref}} ->
            Timeout = if
                ConfigOptions
                #config_service_options.response_timeout_adjustment ->
                    case erlang:cancel_timer(Tref) of
                        false ->
                            0;
                        V ->
                            V
                    end;
                true ->
                    OldTimeout
            end,
            {next_state, StateName,
             send_timeout_end(TransId,
                async_response_timeout_start(ResponseInfo, Response, Timeout,
                                             TransId, State))}
    end;

handle_info({'cloudi_service_return_sync', _, _,
             ResponseInfo, Response, _, _, _}, StateName, State)
    when is_binary(ResponseInfo) =:= false; is_binary(Response) =:= false ->
    {next_state, StateName, State};

handle_info({'cloudi_service_return_sync', _Name, _Pattern,
             ResponseInfo, Response, _Timeout, TransId, Pid}, StateName,
            #state{dispatcher = Dispatcher,
                   send_timeouts = SendTimeouts,
                   options = ConfigOptions} = State) ->
    true = Pid =:= Dispatcher,
    case dict:find(TransId, SendTimeouts) of
        error ->
            % send_sync timeout already occurred
            {next_state, StateName, State};
        {ok, {_, Tref}} ->
            if
                ConfigOptions
                #config_service_options.response_timeout_adjustment ->
                    erlang:cancel_timer(Tref);
                true ->
                    ok
            end,
            send('return_sync_out'(ResponseInfo, Response, TransId), State),
            {next_state, StateName, send_timeout_end(TransId, State)}
    end;

handle_info({'cloudi_service_send_async_timeout', TransId}, StateName,
            #state{send_timeouts = SendTimeouts,
                   options = ConfigOptions} = State) ->
    case dict:find(TransId, SendTimeouts) of
        error ->
            if
                ConfigOptions
                #config_service_options.response_timeout_adjustment ->
                    % should never happen, timer should have been cancelled
                    % if the send_async already returned
                    ?LOG_WARN("send timeout not found (trans_id=~s)",
                              [cloudi_x_uuid:uuid_to_string(TransId)]);
                true ->
                    ok % cancel_timer avoided due to latency
            end,
            {next_state, StateName, State};
        {ok, _} ->
            {next_state, StateName, send_timeout_end(TransId, State)}
    end;

handle_info({'cloudi_service_send_sync_timeout', TransId}, StateName,
            #state{send_timeouts = SendTimeouts,
                   options = ConfigOptions} = State) ->
    case dict:find(TransId, SendTimeouts) of
        error ->
            if
                ConfigOptions
                #config_service_options.response_timeout_adjustment ->
                    % should never happen, timer should have been cancelled
                    % if the send_sync already returned
                    ?LOG_WARN("send timeout not found (trans_id=~s)",
                              [cloudi_x_uuid:uuid_to_string(TransId)]);
                true ->
                    ok % cancel_timer avoided due to latency
            end,
            {next_state, StateName, State};
        {ok, _} ->
            send('return_sync_out'(timeout, TransId), State),
            {next_state, StateName, send_timeout_end(TransId, State)}
    end;

handle_info({'cloudi_service_recv_async_timeout', TransId}, StateName,
            #state{async_responses = AsyncResponses} = State) ->
    {next_state, StateName,
     State#state{async_responses = dict:erase(TransId, AsyncResponses)}};

handle_info({'EXIT', _, Reason}, _, State) ->
    {stop, Reason, State};

handle_info(Request, StateName, State) ->
    ?LOG_WARN("Unknown info \"~p\"", [Request]),
    {next_state, StateName, State}.

terminate(_, _, #state{protocol = tcp,
                       listener = Listener,
                       socket = Socket,
                       os_pid = OsPid}) ->
    catch gen_tcp:close(Listener),
    catch gen_tcp:close(Socket),
    os_pid_kill(OsPid),
    ok;

terminate(_, _, #state{protocol = udp,
                       socket = Socket,
                       os_pid = OsPid}) ->
    catch gen_udp:close(Socket),
    os_pid_kill(OsPid),
    ok;

terminate(_, _, #state{protocol = local,
                       listener = Listener,
                       socket_path = SocketPath,
                       socket = Socket,
                       os_pid = OsPid}) ->
    catch gen_tcp:close(Listener),
    catch gen_udp:close(Socket),
    os_pid_kill(OsPid),
    catch file:delete(SocketPath),
    ok.

code_change(_, StateName, State, _) ->
    {ok, StateName, State}.

%%%------------------------------------------------------------------------
%%% Private functions
%%%------------------------------------------------------------------------

os_pid_kill(undefined) ->
    ok;

os_pid_kill(OsPid) ->
    % if the OsPid exists at this point, it is probably stuck.
    % without this kill, the process could just stay around, while
    % being unresponsive and without its Erlang socket pids.
    os:cmd(cloudi_string:format("kill -9 ~w", [OsPid])).

handle_send_async(Name, RequestInfo, Request, Timeout, Priority, StateName,
                  #state{dispatcher = Dispatcher,
                         uuid_generator = UUID,
                         dest_refresh = DestRefresh,
                         cpg_data = Groups} = State) ->
    case destination_get(DestRefresh, Name, Dispatcher, Groups) of
        {error, _} when Timeout >= ?SEND_ASYNC_INTERVAL ->
            erlang:send_after(?SEND_ASYNC_INTERVAL, Dispatcher,
                              {'cloudi_service_send_async_retry',
                               Name, RequestInfo, Request,
                               Timeout - ?SEND_ASYNC_INTERVAL, Priority}),
            {next_state, StateName, State};
        {error, _} ->
            send('return_async_out'(), State),
            {next_state, StateName, State};
        {ok, Pattern, Pid} ->
            TransId = cloudi_x_uuid:get_v1(UUID),
            Pid ! {'cloudi_service_send_async',
                   Name, Pattern, RequestInfo, Request,
                   Timeout, Priority, TransId, Dispatcher},
            send('return_async_out'(TransId), State),
            {next_state, StateName,
             send_async_timeout_start(Timeout, TransId, State)}
    end.

handle_send_sync(Name, RequestInfo, Request, Timeout, Priority, StateName,
                 #state{dispatcher = Dispatcher,
                        uuid_generator = UUID,
                        dest_refresh = DestRefresh,
                        cpg_data = Groups} = State) ->
    case destination_get(DestRefresh, Name, Dispatcher, Groups) of
        {error, _} when Timeout >= ?SEND_SYNC_INTERVAL ->
            erlang:send_after(?SEND_SYNC_INTERVAL, Dispatcher,
                              {'cloudi_service_send_sync_retry',
                               Name, RequestInfo, Request,
                               Timeout - ?SEND_SYNC_INTERVAL, Priority}),
            {next_state, StateName, State};
        {error, _} ->
            send('return_sync_out'(), State),
            {next_state, StateName, State};
        {ok, Pattern, Pid} ->
            TransId = cloudi_x_uuid:get_v1(UUID),
            Pid ! {'cloudi_service_send_sync',
                   Name, Pattern, RequestInfo, Request,
                   Timeout, Priority, TransId, Dispatcher},
            {next_state, StateName,
             send_sync_timeout_start(Timeout, TransId, undefined, State)}
    end.

handle_mcast_async(Name, RequestInfo, Request, Timeout, Priority, StateName,
                   #state{dispatcher = Dispatcher,
                          uuid_generator = UUID,
                          dest_refresh = DestRefresh,
                          cpg_data = Groups} = State) ->
    case destination_all(DestRefresh, Name, Dispatcher, Groups) of
        {error, _} when Timeout >= ?MCAST_ASYNC_INTERVAL ->
            erlang:send_after(?MCAST_ASYNC_INTERVAL, Dispatcher,
                              {'cloudi_service_mcast_async_retry',
                               Name, RequestInfo, Request,
                               Timeout - ?MCAST_ASYNC_INTERVAL, Priority}),
            {next_state, StateName, State};
        {error, _} ->
            send('returns_async_out'(), State),
            {next_state, StateName, State};
        {ok, Pattern, PidList} ->
            TransIdList = lists:map(fun(Pid) ->
                TransId = cloudi_x_uuid:get_v1(UUID),
                Pid ! {'cloudi_service_send_async',
                       Name, Pattern, RequestInfo, Request,
                       Timeout, Priority, TransId, Dispatcher},
                TransId
            end, PidList),
            send('returns_async_out'(TransIdList), State),
            NewState = lists:foldl(fun(Id, S) ->
                send_async_timeout_start(Timeout, Id, S)
            end, State, TransIdList),
            {next_state, StateName, NewState}
    end.

'init_out'(Prefix, TimeoutAsync, TimeoutSync,
           PriorityDefault, RequestTimeoutAdjustment)
    when is_list(Prefix), is_integer(TimeoutAsync), is_integer(TimeoutSync),
         is_integer(PriorityDefault),
         PriorityDefault >= ?PRIORITY_HIGH, PriorityDefault =< ?PRIORITY_LOW,
         is_boolean(RequestTimeoutAdjustment) ->
    PrefixBin = erlang:list_to_binary(Prefix),
    PrefixSize = erlang:byte_size(PrefixBin) + 1,
    RequestTimeoutAdjustmentInt = if
        RequestTimeoutAdjustment ->
            1;
        true ->
            0
    end,
    <<?MESSAGE_INIT:32/unsigned-integer-native,
      PrefixSize:32/unsigned-integer-native,
      PrefixBin/binary, 0:8,
      TimeoutAsync:32/unsigned-integer-native,
      TimeoutSync:32/unsigned-integer-native,
      PriorityDefault:8/signed-integer-native,
      RequestTimeoutAdjustmentInt:8/unsigned-integer-native>>.

'keepalive_out'() ->
    <<?MESSAGE_KEEPALIVE:32/unsigned-integer-native>>.

'send_async_out'(Name, Pattern, RequestInfo, Request,
                 Timeout, Priority, TransId, Pid)
    when is_list(Name), is_list(Pattern),
         is_binary(RequestInfo), is_binary(Request),
         is_integer(Timeout), is_integer(Priority),
         is_binary(TransId), is_pid(Pid) ->
    NameBin = erlang:list_to_binary(Name),
    NameSize = erlang:byte_size(NameBin) + 1,
    PatternBin = erlang:list_to_binary(Pattern),
    PatternSize = erlang:byte_size(PatternBin) + 1,
    RequestInfoSize = erlang:byte_size(RequestInfo),
    RequestSize = erlang:byte_size(Request),
    PidBin = erlang:term_to_binary(Pid),
    PidSize = erlang:byte_size(PidBin),
    <<?MESSAGE_SEND_ASYNC:32/unsigned-integer-native,
      NameSize:32/unsigned-integer-native,
      NameBin/binary, 0:8,
      PatternSize:32/unsigned-integer-native,
      PatternBin/binary, 0:8,
      RequestInfoSize:32/unsigned-integer-native,
      RequestInfo/binary, 0:8,
      RequestSize:32/unsigned-integer-native,
      Request/binary, 0:8,
      Timeout:32/unsigned-integer-native,
      Priority:8/signed-integer-native,
      TransId/binary,             % 128 bits
      PidSize:32/unsigned-integer-native,
      PidBin/binary>>.

'send_sync_out'(Name, Pattern, RequestInfo, Request,
                Timeout, Priority, TransId, Pid)
    when is_list(Name), is_list(Pattern),
         is_binary(RequestInfo), is_binary(Request),
         is_integer(Timeout), is_integer(Priority),
         is_binary(TransId), is_pid(Pid) ->
    NameBin = erlang:list_to_binary(Name),
    NameSize = erlang:byte_size(NameBin) + 1,
    PatternBin = erlang:list_to_binary(Pattern),
    PatternSize = erlang:byte_size(PatternBin) + 1,
    RequestInfoSize = erlang:byte_size(RequestInfo),
    RequestSize = erlang:byte_size(Request),
    PidBin = erlang:term_to_binary(Pid),
    PidSize = erlang:byte_size(PidBin),
    <<?MESSAGE_SEND_SYNC:32/unsigned-integer-native,
      NameSize:32/unsigned-integer-native,
      NameBin/binary, 0:8,
      PatternSize:32/unsigned-integer-native,
      PatternBin/binary, 0:8,
      RequestInfoSize:32/unsigned-integer-native,
      RequestInfo/binary, 0:8,
      RequestSize:32/unsigned-integer-native,
      Request/binary, 0:8,
      Timeout:32/unsigned-integer-native,
      Priority:8/signed-integer-native,
      TransId/binary,             % 128 bits
      PidSize:32/unsigned-integer-native,
      PidBin/binary>>.

'return_async_out'() ->
    <<?MESSAGE_RETURN_ASYNC:32/unsigned-integer-native,
      0:128>>.                    % 128 bits

'return_async_out'(TransId)
    when is_binary(TransId) ->
    <<?MESSAGE_RETURN_ASYNC:32/unsigned-integer-native,
      TransId/binary>>.           % 128 bits

'return_sync_out'() ->
    <<?MESSAGE_RETURN_SYNC:32/unsigned-integer-native,
      0:32, 0:8,
      0:32, 0:8,
      0:128>>.                    % 128 bits

'return_sync_out'(timeout, TransId)
    when is_binary(TransId) ->
    <<?MESSAGE_RETURN_SYNC:32/unsigned-integer-native,
      0:32, 0:8,
      0:32, 0:8,
      TransId/binary>>.           % 128 bits

'return_sync_out'(ResponseInfo, Response, TransId)
    when is_binary(ResponseInfo), is_binary(Response), is_binary(TransId) ->
    ResponseInfoSize = erlang:byte_size(ResponseInfo),
    ResponseSize = erlang:byte_size(Response),
    <<?MESSAGE_RETURN_SYNC:32/unsigned-integer-native,
      ResponseInfoSize:32/unsigned-integer-native,
      ResponseInfo/binary, 0:8,
      ResponseSize:32/unsigned-integer-native,
      Response/binary, 0:8,
      TransId/binary>>.           % 128 bits

'returns_async_out'() ->
    <<?MESSAGE_RETURNS_ASYNC:32/unsigned-integer-native,
      0:32>>.

'returns_async_out'(TransIdList)
    when is_list(TransIdList) ->
    TransIdListBin = erlang:list_to_binary(TransIdList),
    TransIdListCount = erlang:length(TransIdList),
    <<?MESSAGE_RETURNS_ASYNC:32/unsigned-integer-native,
      TransIdListCount:32/unsigned-integer-native,
      TransIdListBin/binary>>.    % 128 bits * count

'recv_async_out'(timeout, TransId)
    when is_binary(TransId) ->
    <<?MESSAGE_RECV_ASYNC:32/unsigned-integer-native,
      0:32, 0:8,
      0:32, 0:8,
      TransId/binary>>.           % 128 bits

'recv_async_out'(ResponseInfo, Response, TransId)
    when is_binary(ResponseInfo), is_binary(Response), is_binary(TransId) ->
    ResponseInfoSize = erlang:byte_size(ResponseInfo),
    ResponseSize = erlang:byte_size(Response),
    <<?MESSAGE_RECV_ASYNC:32/unsigned-integer-native,
      ResponseInfoSize:32/unsigned-integer-native,
      ResponseInfo/binary, 0:8,
      ResponseSize:32/unsigned-integer-native,
      Response/binary, 0:8,
      TransId/binary>>.           % 128 bits

send(Data, #state{protocol = Protocol,
                  incoming_port = Port,
                  socket = Socket}) when is_binary(Data) ->
    if
        Protocol =:= tcp; Protocol =:= local ->
            ok = gen_tcp:send(Socket, Data);
        Protocol =:= udp ->
            ok = gen_udp:send(Socket, {127,0,0,1}, Port, Data)
    end.

process_queue(#state{recv_timeouts = RecvTimeouts,
                     queue_requests = true,
                     queued = Queue} = State) ->
    case cloudi_x_pqueue4:out(Queue) of
        {empty, NewQueue} ->
            State#state{queue_requests = false,
                        queued = NewQueue};
        {{value, {'cloudi_service_send_async',
                  Name, Pattern, RequestInfo, Request,
                  _, Priority, TransId, Pid}}, NewQueue} ->
            Timeout = case erlang:cancel_timer(dict:fetch(TransId,
                                                          RecvTimeouts)) of
                false ->
                    0;
                V ->    
                    V       
            end,
            send('send_async_out'(Name, Pattern, RequestInfo, Request,
                                  Timeout, Priority, TransId, Pid),
                 State),
            State#state{recv_timeouts = dict:erase(TransId, RecvTimeouts),
                        queued = NewQueue};
        {{value, {'cloudi_service_send_sync',
                  Name, Pattern, RequestInfo, Request,
                  _, Priority, TransId, Pid}}, NewQueue} ->
            Timeout = case erlang:cancel_timer(dict:fetch(TransId,
                                                          RecvTimeouts)) of
                false ->
                    0;
                V ->    
                    V       
            end,
            send('send_sync_out'(Name, Pattern, RequestInfo, Request,
                                 Timeout, Priority, TransId, Pid),
                 State),
            State#state{recv_timeouts = dict:erase(TransId, RecvTimeouts),
                        queued = NewQueue}
    end.

socket_open(tcp, _, _, BufferSize) ->
    SocketOptions = [{recbuf, BufferSize}, {sndbuf, BufferSize},
                     {nodelay, true}, {delay_send, false}, {keepalive, false},
                     {send_timeout, 5000}, {send_timeout_close, true}],
    case gen_tcp:listen(0, [binary, inet, {ip, {127,0,0,1}},
                            {packet, 4}, {backlog, 0},
                            {active, false} | SocketOptions]) of
        {ok, Listener} ->
            {ok, Port} = inet:port(Listener),
            {ok, Acceptor} = prim_inet:async_accept(Listener, -1),
            {ok, #state{protocol = tcp,
                        port = Port,
                        listener = Listener,
                        acceptor = Acceptor,
                        socket_options = SocketOptions}};
        {error, _} = Error ->
            Error
    end;

socket_open(udp, _, _, BufferSize) ->
    SocketOptions = [{recbuf, BufferSize}, {sndbuf, BufferSize}],
    case gen_udp:open(0, [binary, inet, {ip, {127,0,0,1}},
                          {active, once} | SocketOptions]) of
        {ok, Socket} ->
            {ok, Port} = inet:port(Socket),
            {ok, #state{protocol = udp,
                        port = Port,
                        socket_options = SocketOptions,
                        socket = Socket}};
        {error, _} = Error ->
            Error
    end;

socket_open(local, SocketPath, ThreadIndex, BufferSize) ->
    SocketOptions = [{recbuf, BufferSize}, {sndbuf, BufferSize},
                     {nodelay, true}, {delay_send, false}, {keepalive, false},
                     {send_timeout, 5000}, {send_timeout_close, true}],
    ThreadSocketPath = SocketPath ++ erlang:integer_to_list(ThreadIndex),
    case local_listen(ThreadSocketPath,
                      [binary, inet, {ip, {127,0,0,1}}, {packet, 4},
                       {backlog, 0}, {active, false} | SocketOptions],
                      SocketOptions) of
        {ok, State} ->
            {ok, State#state{port = ThreadIndex}};
        {error, _} = Error ->
            Error
    end.

local_listen(SocketPath, InetOptions, SocketOptions) ->
    % carefully grafting unix domain socket support onto an Erlang listener
    {ok, Listener} = gen_tcp:listen(0, InetOptions),
    {ok, FileDescriptor} = prim_inet:getfd(Listener),
    ok = cloudi_socket:local_listen(FileDescriptor, SocketPath),
    {ok, ListenerInet} = gen_tcp:listen(0, InetOptions),
    {ok, Port} = inet:port(ListenerInet),
    {ok, Client} = gen_tcp:connect({127,0,0,1}, Port, [{active, false}]),
    {ok, Socket} = gen_tcp:accept(ListenerInet, 100),
    ok = inet:setopts(Socket, [{active, false} | SocketOptions]),
    catch gen_tcp:close(ListenerInet),
    erlang:send_after(10, self(),
                      {inet_async, Listener, Client, {ok, Socket}}),
    {ok, #state{protocol = local,
                listener = Listener,
                acceptor = Client,
                socket_path = SocketPath,
                socket_options = SocketOptions}}.

local_accept(Listener, Socket, SocketPath, SocketOptions) ->
    % carefully grafting unix domain socket support onto an Erlang socket
    {ok, FileDescriptorIn} = prim_inet:getfd(Listener),
    {ok, FileDescriptorOut} = prim_inet:getfd(Socket),
    ok = prim_inet:ignorefd(Socket, true),
    {recbuf, ReceiveBufferSize} = lists:keyfind(recbuf, 1, SocketOptions),
    {sndbuf, SendBufferSize} = lists:keyfind(sndbuf, 1, SocketOptions),
    {ok, NewSocket} = gen_tcp:fdopen(FileDescriptorOut,
                                     [binary, {packet, 4},
                                      {active, false} | SocketOptions]),
    ok = cloudi_socket:local_accept(FileDescriptorIn,
                                    FileDescriptorOut,
                                    SocketPath,
                                    ReceiveBufferSize,
                                    SendBufferSize),
    ok = inet:setopts(NewSocket, [{active, once}]),
    % NewSocket is used instead of Socket because it is internally marked as
    % prebound (in ERTS) so that Erlang will not attempt to reconnect
    % or make other assumptions about the socket file descriptor
    {ok, NewSocket}.

