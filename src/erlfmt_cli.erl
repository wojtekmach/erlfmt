%% Copyright (c) Facebook, Inc. and its affiliates.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
-module(erlfmt_cli).

-export([opts/0, do/2]).

-record(config, {
    verbose = false :: boolean(),
    out = standard_out :: erlfmt:out()
}).

-spec opts() -> [getopt:option_spec()].
opts() ->
    [
        {help, $h, "help", undefined, "print this message"},
        {version, $v, "version", undefined, "print version"},
        {write, $w, "write", undefined, "modify formatted files in place"},
        {out, $o, "out", binary, "output directory"},
        {verbose, undefined, "verbose", undefined, "include debug output"},
        {files, undefined, undefined, string, "files to format"}
    ].

-spec do(list(), string()) -> ok.
do(Opts, Name) ->
    case parse_opts(Opts, Name, [], #config{}) of
        {format, [], _Config} ->
            io:put_chars(standard_error, "no files to format provided\n\n"),
            getopt:usage(opts(), Name),
            erlang:halt(1);
        {format, Files, Config} ->
            case format_files(Files, Config, false) of
                true -> erlang:halt(4);
                false -> ok
            end
    end.

format_files([FileName | FileNames], Config, HadErrors) ->
    case Config#config.verbose of
        true -> io:format(standard_error, "Formatting ~s\n", [FileName]);
        false -> ok
    end,
    case erlfmt:format_file(FileName, Config#config.out) of
        {ok, Warnings} ->
            [print_error_info(Warning) || Warning <- Warnings],
            format_files(FileNames, Config, HadErrors);
        {error, Error} ->
            print_error_info(Error),
            format_files(FileNames, Config, true)
    end;
format_files([], _Config, HadErrors) ->
    HadErrors.

parse_opts([help | _Rest], Name, _Files, _Config) ->
    getopt:usage(opts(), Name),
    erlang:halt(0);
parse_opts([version | _Rest], Name, _Files, _Config) ->
    {ok, Vsn} = application:get_key(erlfmt, vsn),
    io:format("~s version ~s\n", [Name, Vsn]),
    erlang:halt(0);
parse_opts([write | Rest], Name, Files, Config) ->
    parse_opts(Rest, Name, Files, Config#config{out = replace});
parse_opts([{out, Path} | Rest], Name, Files, Config) ->
    parse_opts(Rest, Name, Files, Config#config{out = {path, Path}});
parse_opts([verbose | Rest], Name, Files, Config) ->
    parse_opts(Rest, Name, Files, Config#config{verbose = true});
parse_opts([{files, NewFiles} | Rest], Name, Files0, Config) ->
    parse_opts(Rest, Name, expand_files(NewFiles, Files0), Config);
parse_opts([], _Name, Files, Config) ->
    {format, lists:reverse(Files), Config}.

expand_files(NewFile, Files) when is_integer(hd(NewFile)) ->
    case filelib:is_regular(NewFile) of
        true ->
            [NewFile | Files];
        false ->
            case filelib:wildcard(NewFile) of
                [] ->
                    io:format(standard_error, "no file matching '~s'", [NewFile]),
                    Files;
                NewFiles ->
                    NewFiles ++ Files
            end
    end;
expand_files(NewFiles, Files) when is_list(NewFiles) ->
    lists:foldl(fun expand_files/2, Files, NewFiles).

print_error_info(Info) ->
    io:put_chars(standard_error, [erlfmt:format_error_info(Info), $\n]).
