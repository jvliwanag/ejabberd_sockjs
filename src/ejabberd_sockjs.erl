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

-module(ejabberd_sockjs).
-author('jvliwanag@gmail.com').

-behavior(gen_server).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-ifndef(TEST).
-define(EJ_SOCKET, ejabberd_socket).
-else.
-define(EJ_SOCKET, test_ejabberd_socket).
-endif.

-include_lib("ejabberd/include/ejabberd.hrl").

-include("ejabberd_sockjs_internal.hrl").

%% API
-export([
	start/1,
	start_link/1,
	start_supervised/1,
	receive_bin/2,
	stop/1
]).

%% ejabberd_socket callbacks
-export([
	controlling_process/2,
	sockname/1,
	peername/1,
	setopts/2,
	custom_receiver/1,
	monitor/1,
	become_controller/2,
	send/2,
	reset_stream/1,

	%% TODO
	change_shaper/2
]).

%% ejabberd_listener callbacks
-export([
	socket_type/0,
	start_listener/2
]).

%% gen_server callbacks
-export([
	init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2,
	code_change/3
]).

-record(state, {
	conn :: sockjs_conn(),
	controller :: pid() | undefined,
	xml_stream_state,
	prebuff = [],
	c2s_pid :: pid() | undefined
}).


-record(sockjs_state, {
	conn_pid :: pid() | undefined
}).

%% API

-spec start(sockjs_conn()) -> {ok, pid()}.
start(Conn) ->
	gen_server:start(?MODULE, [Conn], []).

-spec start_link(sockjs_conn()) -> {ok, pid()}.
start_link(Conn) ->
	gen_server:start_link(?MODULE, [Conn], []).


-spec start_supervised(sockjs_conn()) -> {ok, pid()} | {error, not_started}.
start_supervised(Conn) ->
	?DEBUG("Starting sockjs session", []),
	case catch supervisor:start_child(ejabberd_sockjs_sup, [Conn]) of
		{ok, Pid} ->
			{ok, Pid};
		_Err ->
			?WARNING_MSG("Error starting sockjs session: ~p", [_Err]),
			{error, not_started}
	end.

-spec receive_bin(pid(), binary()) -> ok.
receive_bin(SrvRef, Bin) ->
	gen_server:cast(SrvRef, {receive_bin, Bin}).

-spec stop(pid()) -> ok.
stop(SrvRef) ->
    gen_server:cast(SrvRef, close_session).

%% ejabberd_socket callbacks

-spec controlling_process(sock(), pid()) -> ok.
% controlling_process({sockjs, SrvRef, _Conn}, Pid) ->
% 	gen_server:call(SrvRef, {controlling_process, Pid}).
controlling_process({sockjs, _SrvRef, _Conn}, _Pid) ->
	ok.

%% TODO
-spec change_shaper(pid(), any()) -> ok.
change_shaper(_SrvRef, _Shaper) ->
	ok.

-spec sockname(sock()) -> {ok, inet:ip_address(), inet:port_number()}.
sockname({sockjs, _SrvRef, Conn}) ->
	Info = sockjs_session:info(Conn),
	Sockname = proplists:get_value(sockname, Info),
	{ok, Sockname}.

-spec peername(sock()) -> {ok, inet:ip_address(), inet:port_number()}.
peername({sockjs, _SrvRef, Conn}) ->
	Info = sockjs_session:info(Conn),
	Sockname = proplists:get_value(peername, Info),
	{ok, Sockname}.

-spec setopts(sock(), [any()]) -> ok.
setopts(_Sock, _Opts) ->
	%% TODO implement {active, once}
	ok.

-spec custom_receiver(sock()) -> {receiver, ?MODULE, pid()}.
custom_receiver({sockjs, SrvRef, _Conn}) ->
	{receiver, ?MODULE, SrvRef}.

-spec monitor(sock()) -> reference().
monitor({sockjs, SrvRef, _Conn}) ->
	erlang:monitor(process, SrvRef).

-spec become_controller(pid(), C2SPid :: pid()) -> ok.
become_controller(SrvRef, C2SPid) ->
	gen_server:cast(SrvRef, {become_controller, C2SPid}).

-spec send(sock(), iolist()) -> ok.
send({sockjs, SrvRef, _Conn}, Out) ->
	gen_server:cast(SrvRef, {send, Out}).

-spec reset_stream(sock()) -> ok.
reset_stream({sockjs, SrvRef, _Conn}) ->
	gen_server:cast(SrvRef, reset_stream).

%% ejabberd_listener callbacks
-spec socket_type() -> independent.
socket_type() ->
	independent.

-type listener_opt() :: ok.
-type ip_port_tcp() :: {inet:port_number(), inet:ip4_address(), tcp}.
-spec start_listener(ip_port_tcp(), [listener_opt()]) -> {ok, pid()}.
start_listener({Port, Ip, _}, Opts) ->
	start_app(cowboy),
	start_app(sockjs),

	Path = proplists:get_value(path, Opts, "/sockjs"),
	Prefix = proplists:get_value(prefix, Opts, Path),
	PrefixBin = list_to_binary(Prefix),

	PathPattern = [list_to_binary(X) || X <- string:tokens(Path, "/")] ++ ['...'],

	SockjsState = sockjs_handler:init_state(PrefixBin, fun service_ej/3, #sockjs_state{}, []),
	Routes = [{'_', [{PathPattern, sockjs_cowboy_handler, SockjsState}]}],

	cowboy:start_listener({ejabberd_sockjs_http, Port}, 100,
		cowboy_tcp_transport, [{port, Port}, {ip, Ip}],
		cowboy_http_protocol, [{dispatch, Routes}]).

%% gen_server callbacks
init([Conn]) ->
	Socket = {sockjs, self(), Conn},
	?EJ_SOCKET:start(ejabberd_c2s, ?MODULE, Socket, []),
	?DEBUG("Sockjs session started", []),

	{ok, #state{conn = Conn}}.

handle_call(_Msg, _From, St) ->
	?WARNING_MSG("Unknown msg: ~p", [_Msg]),
	{reply, {error, unknown_msg}, St}.

% handle_call({controlling_process, Pid}, _From, St) ->
% 	case St#state.controller of
% 		P when is_pid(P) ->
% 			unlink(P);
% 		_ ->
% 			ok
% 	end,

% 	link(Pid),
% 	{reply, ok, St#state{controller = Pid}}.

handle_cast({become_controller, C2SPid}, St) ->
	%% TODO max stanza size
	XMLStreamInitSt = xml_stream:new(C2SPid),

	PreBuff = lists:reverse(St#state.prebuff),
	XMLStreamSt = lists:foldl(fun(Bin, XSt) ->
		xml_stream:parse(XSt, Bin)
	end, XMLStreamInitSt, PreBuff),

	NSt = St#state{xml_stream_state = XMLStreamSt,
		prebuff = [], c2s_pid = C2SPid},
	{noreply, NSt};
handle_cast({receive_bin, Bin}, St) ->
	?DEBUG("Receive: ~p", [Bin]),
	NSt = case St#state.xml_stream_state of
		undefined ->
			PreBuff = St#state.prebuff,
			St#state{prebuff = [Bin|PreBuff]};
		XMLStreamSt ->
			NXMLStreamSt = xml_stream:parse(XMLStreamSt, Bin),
			St#state{xml_stream_state = NXMLStreamSt}
	end,
	{noreply, NSt};
handle_cast({send, Out}, St) ->
	?DEBUG("Sending: ~p", [Out]),
	Conn = St#state.conn,
	sockjs_session:send(Out, Conn),
	{noreply, St};
handle_cast(reset_stream, St) ->
	XMLStreamSt = St#state.xml_stream_state,
	C2SPid = St#state.c2s_pid,

	xml_stream:close(XMLStreamSt),

	NXMLStreamSt = xml_stream:new(C2SPid),
	NSt = St#state{xml_stream_state = NXMLStreamSt},
	{noreply, NSt};

handle_cast(close_session, St) ->
	case St#state.c2s_pid of
        P when is_pid(P) ->
            ejabberd_c2s:stop(P);
        _ ->
            ok
    end,
    xml_stream:close(St#state.xml_stream_state),
    {stop, normal, St}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal

service_ej(Conn, init, State) ->
	{ok, Pid} = ejabberd_sockjs:start_supervised(Conn),

	{ok, State#sockjs_state{conn_pid = Pid}};
service_ej(_Conn, {recv, Data}, State) ->
	Pid = State#sockjs_state.conn_pid,
	ejabberd_sockjs:receive_bin(Pid, Data),
	{ok, State};
service_ej(_Conn, closed, State) ->
    Pid = State#sockjs_state.conn_pid,
    gen_server:cast(Pid, close_session),
	{ok, State}.

start_app(App) ->
	case application:start(App) of
		ok -> ok;
		{error, {already_started, _}} -> ok
	end.

%% EUnit Tests
-ifdef(TEST).

t_sock() ->
	{ok, Pid} = start(t_con()),
	t_sock(Pid).

t_sock(Pid) ->
	{sockjs, Pid, t_con()}.

% t_pid() ->
% 	spawn_link(fun() -> receive _ -> ok end end).

t_con() ->
	%% Hmm. or use meck?
	{sockjs_session,{self(),
     [{peername,{{127,0,0,1},58105}},
      {sockname,{{127,0,0,1},8081}},
      {path,"/sockjs/741/xkeaw5sg/websocket"},
      {headers,[]}]}}.

start_test() ->
	erlang:register(ejsock_starter_pid, self()),
	Sock = t_sock(),
	SocketInitd = receive
		{ejsocket, ejabberd_c2s, ?MODULE, Sock, []} -> true;
		_A -> ?debugVal(_A), false
	after 100 -> false
	end,
	?assert(SocketInitd).

% controlling_process_test() ->
% 	{setup, fun() ->
% 		meck:new(ejabberd_socket)
% 	end, fun() ->
% 		meck:unload()
% 	end, [fun() ->
% 	{ok, Pid} = start(t_con()),
% 	Sock = t_sock(Pid),

% 	Pid1 = t_pid(),
% 	Pid2 = t_pid(),

% 	%% Initial set
% 	?assertEqual(ok, controlling_process(Sock, Pid1)),
% 	{links, Links} = erlang:process_info(Pid, links),
% 	?assert(lists:member(Pid1, Links)),

% 	%% Replacement
% 	?assertEqual(ok, controlling_process(Sock, Pid2)),
% 	{links, Links2} = erlang:process_info(Pid, links),
% 	?assert(lists:member(Pid2, Links2)),
% 	?assert(not lists:member(Pid1, Links2)).

sockname_peername_test() ->
	Sock = t_sock(),

	?assertEqual({ok, {{127,0,0,1},8081}},
		sockname(Sock)),

	?assertEqual({ok, {{127,0,0,1},58105}},
		peername(Sock)).

setopts_test() ->
	?assertEqual(ok, setopts(t_sock(), [])).

custom_receiver_test() ->
	{ok, Pid} = start(t_con()),
	Sock = t_sock(Pid),
	?assertEqual({receiver, ?MODULE, Pid},
		custom_receiver(Sock)).

monitor_test() ->
	Ref = monitor(t_sock()),
	?assertEqual(true, erlang:demonitor(Ref)).

become_controller_then_rcv_test() ->
	load_xml_stream(),
	{_, Pid, _} = t_sock(),

	become_controller(Pid, self()),
	receive_bin(Pid, <<"<stream>">>),

	?assert(received_start("stream")).

rcv_before_become_controller_test() ->
	load_xml_stream(),
	{_, Pid, _} = t_sock(),

	receive_bin(Pid, <<"<stream>">>),
	become_controller(Pid, self()),

	?assert(received_start("stream")).

send_test() ->
	Sock = t_sock(),
	Out = ["hello", <<"world">>],

	send(Sock, Out),
	Sent = receive
		{_, {send, Out}} -> true
	after 100 -> false
	end,

	?assert(Sent).

reset_test() ->
	load_xml_stream(),
	Sock = {_, Pid, _} = t_sock(),

	become_controller(Pid, self()),
	receive_bin(Pid, <<"<a>">>),
	reset_stream(Sock),
	receive_bin(Pid, <<"<b>">>),

	?assert(received_start("a")),
	?assert(received_start("b")).

%% ejabberd_listener tests
start_listener_test() ->
	start_listener({{127, 0, 0, 1}, 9433, tcp}, []),
	Apps = application:loaded_applications(),

	?assert(is_application_started(cowboy)),
	?assert(is_application_started(sockjs)),

	%% TODO test actual start - meck?

	ok.

is_application_started(App) ->
	lists:any(fun({A, _, _}) -> A =:= App end,
		application:which_applications()).

socket_type_test() ->
	?assertEqual(independent, socket_type()).

%% Utils

load_xml_stream() ->
	erl_ddll:load_driver(ejabberd:get_so_path(), expat_erl).

received_start(Name) ->
	receive
		{_, {xmlstreamstart,Name, _}} -> true
	after 100 -> false
	end.

-endif.