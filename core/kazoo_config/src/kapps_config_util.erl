%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2018, 2600Hz
%%% @doc
%%% @author Roman Galeev
%%% @end
%%%-----------------------------------------------------------------------------
-module(kapps_config_util).

-include("kazoo_config.hrl").

-export([get_config/2
        ,get_reseller_config/2
        ,load_config_from_account/2
        ,account_schema_name/1
        ,system_schema_name/1
        ,account_schema/1
        ,system_schema/1
        ,system_config_document_schema/1

        ,account_doc_id/1
        ]).

-spec account_doc_id(kz_term:ne_binary()) -> kz_term:ne_binary().
account_doc_id(Category) -> <<(?KZ_ACCOUNT_CONFIGS)/binary, Category/binary>>.

-spec get_config(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_json:object().
get_config(Account, Config) ->
    Programm = [fun load_config_from_account/2
               ,fun load_config_from_reseller/2
               ,fun load_config_from_system/2
               ,fun load_default_config/2
               ],
    Schema = account_schema(Config),
    kz_json_schema:filter(get_config(Account, Config, Programm), Schema).

-spec get_config(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:functions()) -> kz_json:object().
get_config(Account, Config, Programm) ->
    Confs = [maybe_new(P(Account, Config)) || P <- Programm],
    kz_json:merge(lists:reverse(Confs)).

-spec get_reseller_config(kz_term:ne_binary(), kz_term:ne_binary()) -> kz_json:object().
get_reseller_config(Account, Config) ->
    Programm = [fun load_config_from_reseller/2
               ,fun load_config_from_system/2
               ,fun load_default_config/2
               ],
    Schema = account_schema(Config),
    kz_json_schema:filter(get_config(Account, Config, Programm), Schema).

-spec load_config_from_account(kz_term:api_binary(), kz_term:ne_binary()) -> {ok, kz_json:object()} | {error, any()}.
load_config_from_account(undefined, _Config) -> {ok, kz_json:new()};
load_config_from_account(Account, Config) ->
    AccountDb = kz_util:format_account_db(Account),
    kz_datamgr:open_cache_doc(AccountDb, account_doc_id(Config), [{cache_failures, [not_found]}]).

-spec load_config_from_reseller(kz_term:api_binary(), kz_term:ne_binary()) -> {ok, kz_json:object()} | {error, any()}.
load_config_from_reseller(undefined, _Config) -> {error, not_found};
load_config_from_reseller(Account, Config) ->
    case kz_services:find_reseller_id(Account) of
        undefined -> {error, not_found};
        %% should get from direct reseller only
        %% same logic as kapps_account_config:get_from_reseller
        Account -> {error, not_found};
        ResellerId -> load_config_from_account(ResellerId, Config)
    end.

-spec load_config_from_system(kz_term:api_binary(), kz_term:ne_binary()) -> {ok, kz_json:object()}.
load_config_from_system(_Account, Config) ->
    {'ok', kz_json:get_value(<<"default">>, maybe_new(kapps_config:get_category(Config)), kz_json:new())}.

-spec load_default_config(kz_term:api_binary(), kz_term:ne_binary()) -> {ok, kz_json:object()}.
load_default_config(_Account, Config) ->
    Schema = system_schema(Config),
    {'ok', kz_doc:set_id(kz_json_schema:default_object(Schema), account_doc_id(Config))}.

-spec maybe_new({'ok', kz_json:object()} | {'error', any()}) -> kz_json:object().
maybe_new({'ok', JObj}) -> JObj;
maybe_new({'error', _}) -> kz_json:new().

-spec account_schema_name(kz_term:ne_binary()) -> kz_term:ne_binary().
account_schema_name(Config) when is_binary(Config) ->
    <<"account_config.", Config/binary>>.

-spec system_schema_name(kz_term:ne_binary()) -> kz_term:ne_binary().
system_schema_name(Config) when is_binary(Config) ->
    <<"system_config.", Config/binary>>.

-spec system_schema(kz_term:ne_binary()) -> kz_json:object().
system_schema(Config) when is_binary(Config) ->
    Name = system_schema_name(Config),
    case kz_json_schema:load(Name) of
        {'ok', Schema} -> Schema;
        _ -> system_config_no_schema()
    end.

-spec account_schema(kz_term:ne_binary()) -> kz_json:object().
account_schema(Config) when is_binary(Config) ->
    Name = account_schema_name(Config),
    case kz_json_schema:load(Name) of
        {'ok', Schema} -> Schema;
        _ -> system_config_no_schema()
    end.

-spec system_config_no_schema() -> kz_json:object().
system_config_no_schema() ->
    Flat = [
            {[<<"$schema">>],<<"http://json-schema.org/draft-04/schema#">>}
           ,{[<<"id">>], <<"system_config">>}
           ,{[<<"properties">>, <<"id">>, <<"type">>], <<"string">>}
           ,{[<<"type">>], <<"object">>}
           ],
    kz_json:expand(kz_json:from_list(Flat)).

-spec system_config_no_document_schema() -> kz_json:object().
system_config_no_document_schema() ->
    Flat = [
            {[<<"$schema">>],<<"http://json-schema.org/draft-04/schema#">>}
           ,{[<<"id">>], <<"system_config">>}
           ,{[<<"properties">>, <<"id">>, <<"type">>], <<"string">>}
           ,{[<<"patternProperties">>, <<"(?!id\b)\b\w+">>, <<"type">>], <<"object">>}
           ,{[<<"type">>], <<"object">>}
           ],
    kz_json:expand(kz_json:from_list(Flat)).

-spec system_config_document_schema(kz_term:ne_binary()) -> kz_json:object().
system_config_document_schema(Id) ->
    Name = system_schema_name(Id),
    case kz_json_schema:load(Name) of
        {'ok', _Schema} -> get_system_config_document_schema(Id);
        _ -> system_config_no_document_schema()
    end.

-spec get_system_config_document_schema(kz_term:ne_binary()) -> kz_json:object().
get_system_config_document_schema(Id) ->
    Flat = [
            {[<<"$schema">>],<<"http://json-schema.org/draft-04/schema#">>}
           ,{[<<"id">>], <<"system_config">>}
           ,{[<<"type">>], <<"object">>}
           ,{[<<"properties">>, <<"id">>, <<"type">>], <<"string">>}
           ,{[<<"properties">>, <<"default">>, <<"default">>], kz_json:new()}
           ,{[<<"properties">>, <<"default">>, <<"type">>], <<"object">>}
           ,{[<<"properties">>, <<"default">>, <<"$ref">>], system_schema_name(Id)}
           ,{[<<"patternProperties">>, <<"(?!id\b)\b\w+">>, <<"$ref">>], system_schema_name(Id)}
           ,{[<<"patternProperties">>, <<"(?!id\b)\b\w+">>, <<"type">>], <<"object">>}
           ],
    kz_json:expand(kz_json:from_list(Flat)).
