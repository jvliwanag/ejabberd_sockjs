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

-module(ejabberd_logger).

-export([debug_msg/4, info_msg/4, warning_msg/4, error_msg/4, critical_msg/4]).

debug_msg(_Mod, _Line, _Fmt, _Args) -> ok.
info_msg(_Mod, _Line, _Fmt, _Args) -> ok.
warning_msg(_Mod, _Line, _Fmt, _Args) -> ok.
error_msg(_Mod, _Line, _Fmt, _Args) -> ok.
critical_msg(_Mod, _Line, _Fmt, _Args) -> ok.