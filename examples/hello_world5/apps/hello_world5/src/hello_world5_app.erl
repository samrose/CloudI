%-*-Mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et nomod:

-module(hello_world5_app).

-behaviour(application).

%% application callbacks
-export([start/2,
         stop/1]).

-record(state,
    {
        service_ids = [] :: list(cloudi_service_api:service_id())
    }).

%%%------------------------------------------------------------------------
%%% External interface functions
%%%------------------------------------------------------------------------

%%-------------------------------------------------------------------------
%% @doc
%% ===Start the Hello World 5 application.===
%% @end
%%-------------------------------------------------------------------------

-spec start(_StartType :: normal | {takeover, node()} | {failover, node()},
            _StartArgs :: any()) ->
    {ok, Pid :: pid()} |
    {ok, Pid :: pid(), State :: any()} |
    {error, Reason :: any()}.

start(_StartType, _StartArgs) ->
    {ok, Application} = application:get_application(),
    Services = [
        % All services have automatic_loading = false
        % to rely on the hello_world5 release loading modules

        % CloudI Service API usage through service requests
        [{prefix, "/cloudi/api/"},
         {module, cloudi_service_api_requests},
         {options, [{automatic_loading, false}]}],

        % hello_world5 example
        [{prefix, "/examples/"},
         {module, hello_world5},
         {dest_refresh, none},
         {options,
          [% automatic_loading should be set to false due to the
           % hello_world5 Erlang application handling the loading of
           % Erlang modules for the hello_world5 CloudI service
           {automatic_loading, false},
           % it is not necessary to set the application_name unless the
           % CloudI service name is different from the Erlang application
           % name (in this example, both are named hello_world5,
           % but Erlang applications with more than 1 CloudI service will
           % want to set the application_name here)
           {application_name, Application}]}],

        % hello_world5 example
        % proplist configuration format defaults shown below:
        [%{type, internal}, % gets inferred from having module entry
         {prefix, "/examples/"},
         {module, hello_world5},
         %{args, []}, % default
         %{dest_refresh, immediate_closest}, % default
         %{timeout_init, 5000}, % default
         %{timeout_async, 5000}, % default
         %{timeout_sync, 5000}, % default
         %{dest_list_deny, undefined}, % default
         %{dest_list_allow, undefined}, % default
         %{count_process, 1}, % default
         %{max_r, 5}, % default
         %{max_t, 300}, % default
         {options,
          [{automatic_loading, false},
           {application_name, Application}]}],

        % cloudi_service_http_cowboy gets listed last so that
        % if the destination refresh method changes to lazy,
        % all service name pattern subscriptions are present at initialization
        [{prefix, "/tests/http/"},
         {module, cloudi_service_http_cowboy},
         {args, [{port, 6464}]},
         {options, [{automatic_loading, false}]}]],
    case hello_world5_sup:start_link() of
        {ok, Pid} ->
            case cloudi_service_api:services_add(Services, infinity) of
                {ok, ServiceIds} ->
                    {ok, Pid, #state{service_ids = ServiceIds}};
                {error, _} = Error ->
                    Error
            end;
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Stop the Hello World 5 application.===
%% @end
%%-------------------------------------------------------------------------

-spec stop(State :: any()) ->
    'ok'.

stop(#state{service_ids = ServiceIds}) ->
    ok = cloudi_service_api:services_remove(ServiceIds, infinity),
    ok.

%%%------------------------------------------------------------------------
%%% Private functions
%%%------------------------------------------------------------------------

