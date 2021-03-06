%-*-Mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et nomod:
%%%
%%%------------------------------------------------------------------------
%%% @doc
%%% ==CloudI Service Configuration Arguments Type Checking==
%%% Functions to simplify validation done during service initialization.
%%% @end
%%%
%%% BSD LICENSE
%%% 
%%% Copyright (c) 2015-2016, Michael Truog <mjtruog at gmail dot com>
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
%%% @copyright 2015-2016 Michael Truog
%%% @version 1.5.2 {@date} {@time}
%%%------------------------------------------------------------------------

-module(cloudi_args_type).
-author('mjtruog [at] gmail (dot) com').

%% external interface
-export([function_required/2,
         function_required_pick/2,
         function_optional/2,
         service_name_suffix/2,
         service_name_pattern_suffix/2]).

-include_lib("cloudi_core/include/cloudi_logger.hrl").

%%%------------------------------------------------------------------------
%%% External interface functions
%%%------------------------------------------------------------------------

-spec function_required({{module(), arity()}} | {module(), atom()} | fun(),
                        Arity :: non_neg_integer()) ->
    fun().

function_required({{M, F}}, Arity)
    when is_atom(M), is_atom(F), is_integer(Arity), Arity >= 0 ->
    case erlang:function_exported(M, F, 0) of
        true ->
            Function = M:F(),
            if
                is_function(Function) ->
                    function_required(Function, Arity);
                true ->
                    ?LOG_ERROR_SYNC("function ~w:~w/~w does not "
                                    "return a function!", [M, F, 0]),
                    erlang:exit(badarg)
            end;
        false ->
            ?LOG_ERROR_SYNC("function ~w:~w/~w does not exist!", [M, F, 0]),
            erlang:exit(badarg)
    end;
function_required({M, F}, Arity)
    when is_atom(M), is_atom(F), is_integer(Arity), Arity >= 0 ->
    case erlang:function_exported(M, F, Arity) of
        true ->
            fun M:F/Arity;
        false ->
            ?LOG_ERROR_SYNC("function ~w:~w/~w does not exist!",
                            [M, F, Arity]),
            erlang:exit(badarg)
    end;
function_required(Function, Arity)
    when is_function(Function) ->
    if
        is_function(Function, Arity) ->
            Function;
        true ->
            ?LOG_ERROR_SYNC("function arity is not ~w!", [Arity]),
            erlang:exit(badarg)
    end;
function_required(Function, _) ->
    ?LOG_ERROR_SYNC("not a function: ~p", [Function]),
    erlang:exit(badarg).

-spec function_required_pick({{module(), atom()}} | {module(), atom()} | fun(),
                             ArityOrder :: nonempty_list(non_neg_integer())) ->
    {fun(), Arity :: non_neg_integer()}.

function_required_pick({{M, F}}, [_ | _] = ArityOrder)
    when is_atom(M), is_atom(F) ->
    case erlang:function_exported(M, F, 0) of
        true ->
            Function = M:F(),
            if
                is_function(Function) ->
                    function_required_pick(Function, ArityOrder);
                true ->
                    ?LOG_ERROR_SYNC("function ~w:~w/~w does not "
                                    "return a function!", [M, F, 0]),
                    erlang:exit(badarg)
            end;
        false ->
            ?LOG_ERROR_SYNC("function ~w:~w/~w does not exist!", [M, F, 0]),
            erlang:exit(badarg)
    end;
function_required_pick({M, F}, [_ | _] = ArityOrder)
    when is_atom(M), is_atom(F) ->
    function_required_pick_module(ArityOrder, M, F, ArityOrder);
function_required_pick(Function, [_ | _] = ArityOrder)
    when is_function(Function) ->
    function_required_pick_function(ArityOrder, Function, ArityOrder);
function_required_pick(Function, [_ | _]) ->
    ?LOG_ERROR_SYNC("not a function: ~p", [Function]),
    erlang:exit(badarg).

-spec function_optional(undefined |
                        {{module(), atom()}} | {module(), atom()} | fun(),
                        Arity :: non_neg_integer()) ->
    undefined | fun().

function_optional(undefined, _) ->
    undefined;
function_optional(Function, Arity) ->
    function_required(Function, Arity).

-spec service_name_suffix(Prefix :: cloudi:service_name_pattern(),
                          Name :: cloudi:service_name()) ->
    string().

service_name_suffix([PrefixC | _] = Prefix, [NameC | _] = Name)
    when is_integer(PrefixC), is_integer(NameC) ->
    case lists:member($*, Name) of
        true ->
            ?LOG_ERROR_SYNC("service name is pattern: \"~s\"", [Name]),
            erlang:exit(badarg);
        false ->
            case cloudi_x_trie:pattern_suffix(Prefix, Name) of
                error ->
                    ?LOG_ERROR_SYNC("prefix service name mismatch: "
                                    "\"~s\" \"~s\"", [Prefix, Name]),
                    erlang:exit(badarg);
                Suffix ->
                    Suffix
            end
    end;
service_name_suffix([PrefixC | _], Name)
    when is_integer(PrefixC) ->
    ?LOG_ERROR_SYNC("invalid service name: ~p", [Name]),
    erlang:exit(badarg);
service_name_suffix(Prefix, [NameC | _])
    when is_integer(NameC) ->
    ?LOG_ERROR_SYNC("invalid prefix: ~p", [Prefix]),
    erlang:exit(badarg).

-spec service_name_pattern_suffix(Prefix :: cloudi:service_name_pattern(),
                                  Pattern :: cloudi:service_name_pattern()) ->
    string().

service_name_pattern_suffix([PrefixC | _] = Prefix, [PatternC | _] = Pattern)
    when is_integer(PrefixC), is_integer(PatternC) ->
    case suffix_pattern_parse(Prefix, Pattern) of
        error ->
            ?LOG_ERROR_SYNC("prefix service name pattern mismatch: "
                            "\"~s\" \"~s\"", [Prefix, Pattern]),
            erlang:exit(badarg);
        Suffix ->
            Suffix
    end;
service_name_pattern_suffix([PrefixC | _], Pattern)
    when is_integer(PrefixC) ->
    ?LOG_ERROR_SYNC("invalid service name pattern: ~p", [Pattern]),
    erlang:exit(badarg);
service_name_pattern_suffix(Prefix, [PatternC | _])
    when is_integer(PatternC) ->
    ?LOG_ERROR_SYNC("invalid prefix: ~p", [Prefix]),
    erlang:exit(badarg).

%%%------------------------------------------------------------------------
%%% Private functions
%%%------------------------------------------------------------------------

function_required_pick_module([Arity | ArityL], M, F, ArityOrder)
    when is_integer(Arity), Arity >= 0 ->
    case erlang:function_exported(M, F, Arity) of
        true ->
            {fun M:F/Arity, Arity};
        false ->
            if
                ArityL == [] ->
                    ?LOG_ERROR_SYNC("function ~w:~w/~w does not exist!",
                                    [M, F, ArityOrder]),
                    erlang:exit(badarg);
                true ->
                    function_required_pick_module(ArityL, M, F, ArityOrder)
            end
    end;
function_required_pick_module(_, _, _, ArityOrder) ->
    erlang:exit({badarg, ArityOrder}).

function_required_pick_function([Arity | ArityL], Function, ArityOrder)
    when is_integer(Arity), Arity >= 0 ->
    if
        is_function(Function, Arity) ->
            {Function, Arity};
        ArityL == [] ->
            ?LOG_ERROR_SYNC("function arity is not in ~w!", [ArityOrder]),
            erlang:exit(badarg);
        true ->
            function_required_pick_function(ArityL, Function, ArityOrder)
    end;
function_required_pick_function(_, _, ArityOrder) ->
    erlang:exit({badarg, ArityOrder}).

suffix_pattern_parse([], Pattern) ->
    Pattern;
suffix_pattern_parse([C | Prefix], [C | Pattern]) ->
    suffix_pattern_parse(Prefix, Pattern);
suffix_pattern_parse([_ | _], _) ->
    error.

