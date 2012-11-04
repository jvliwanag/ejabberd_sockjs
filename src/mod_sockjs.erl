%%%----------------------------------------------------------------------
%%%
%%% Copyright (c) 2012, Jan Vincent Liwanag <jvliwanag@gmail.com>
%%%
%%% This file is part of ejabberd_sockjs.
%%%
%%% ejabberd_sockjs is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% ejabberd_sockjs is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with ejabberd_sockjs.  If not, see <http://www.gnu.org/licenses/>.
%%%
%%%----------------------------------------------------------------------

-module(mod_sockjs).
-author('jvliwanag@gmail.com').

% -behavior(gen_mod).

%% gen_mod callbacks
-export([
	start/2,
	stop/1
]).

-include("ejabberd_sockjs_internal.hrl").

-record(state, {host, conn_pid}).

%% gen_mod
start(Host, _Opts) ->
	Proc = gen_mod:get_module_proc(Host, ?PROCNAME_MSJ),
	ChildSpec =
		{Proc,
			{ejabberd_tmp_sup, start_link,
				[Proc, ejabberd_sockjs]},
			permanent,
			infinity,
			supervisor,
			[ejabberd_tmp_sup]},
	supervisor:start_child(ejabberd_sup, ChildSpec),

	application:start(cowboy),
	application:start(sockjs),

	State = #state{host=Host},
	SockjsState = sockjs_handler:init_state(<<"/sockjs">>, fun service_ej/3, State, []),
	Routes = [{'_',  [{[<<"sockjs">>, '...'], sockjs_cowboy_handler, SockjsState}]}],

	cowboy:start_listener(ejabberd_sockjs_http, 100,
		cowboy_tcp_transport, [{port, 8081}],
		cowboy_http_protocol, [{dispatch, Routes}]),

	ok.

stop(_Host) ->
	ok.

%% sockjs
service_ej(Conn, init, State) ->
	Host = State#state.host,
	{ok, Pid} = ejabberd_sockjs:start_supervised(Host, Conn),

	{ok, State#state{conn_pid = Pid}};
service_ej(_Conn, {recv, Data}, State) ->
	Pid = State#state.conn_pid,
	ejabberd_sockjs:receive_bin(Pid, Data),
	{ok, State};
service_ej(_Conn, closed, State) ->
	{ok, State}.