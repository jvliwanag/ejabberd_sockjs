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

-module(test_ejabberd_socket).

-include_lib("eunit/include/eunit.hrl").

-export([start/4]).

start(Mod, SockMod, Socket, Opts) ->
	catch ejsock_starter_pid ! {ejsocket, Mod, SockMod, Socket, Opts},
	ok.