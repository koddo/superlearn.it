begin;
set local role admin_role;



create or replace function create_card(the_user_id integer, the_prev_revision_id uuid, new_front text, new_back text) returns uuid as $$
declare
    new_id uuid;
begin
insert into cards(front, back, prev_revision_id, created_by)
    values(new_front, new_back, the_prev_revision_id, the_user_id)
    returning id into new_id;
return new_id;
end;
$$ language plpgsql;



create or replace function add_card(the_user_id integer, the_card_id uuid, the_due_date date, the_packed_progress_data bigint) returns void as $$
begin
if not has_card(the_user_id, the_card_id) then
insert into cards_orset(user_id, card_id, due_date, packed_progress_data)
    values(the_user_id, the_card_id, the_due_date, the_packed_progress_data);
end if;
end;
$$ language plpgsql;



create or replace function remove_card(the_user_id integer, the_card_id uuid) returns void as $$
begin
update cards_orset set removed_at = now()
    where user_id = the_user_id and card_id = the_card_id and removed_at is null;
end;
$$ language plpgsql;



create or replace function remove_card_from_all_decks(the_user_id integer, the_card_id uuid) returns void as $$
begin
update card_decks_orset set removed_at = now()
where user_id = the_user_id
    and card_id = the_card_id
    and removed_at is null;
end;
$$ language plpgsql;



create or replace function remove_all_contexts_from_card(the_user_id integer, the_card_id uuid) returns void as $$
begin
update card_contexts_orset as s set removed_at = now()
where s.user_id = the_user_id
    and s.card_id = the_card_id
    and s.removed_at is null;
end;
$$ language plpgsql;



create or replace function remove_card_from_orset_decks_contexts(the_user_id integer, the_card_id uuid) returns void as $$
select remove_card(the_user_id, the_card_id);
select remove_card_from_all_decks(the_user_id, the_card_id);
select remove_all_contexts_from_card(the_user_id, the_card_id);
$$ language sql;



create or replace function has_card(the_user_id integer, the_card_id uuid) returns boolean as $$
begin
return exists(
    select 1 from cards_orset as s
    where s.user_id = the_user_id
        and s.card_id = the_card_id
        and s.removed_at is null
        );
end;
$$ language plpgsql;



create or replace function has_card_with_front(the_user_id integer, the_front text) returns boolean as $$
begin
return exists(
    select 1 from cards_orset as s
    join cards as c on c.id = s.card_id
    where s.user_id = the_user_id
        and c.front = the_front
        and s.removed_at is null
        );
end;
$$ language plpgsql;



create or replace function edit_card_content(the_user_id integer, the_card_id uuid, new_front text, new_back text) returns uuid as $$
declare
   new_card_id uuid;
begin
select * into new_card_id from create_card(the_user_id, the_card_id, new_front, new_back);
perform add_card(the_user_id, new_card_id, s.due_date, s.packed_progress_data)
    from cards_orset as s
    where s.user_id = the_user_id
      and s.card_id = the_card_id
      and s.removed_at is null;
perform remove_card(the_user_id, the_card_id);
perform add_card_to_deck(the_user_id, new_card_id, s.deck_id)
    from card_decks_orset as s
    where s.user_id = the_user_id
      and s.card_id = the_card_id
      and s.removed_at is null;
perform remove_card_from_all_decks(the_user_id, the_card_id);
perform add_context_to_card(the_user_id, new_card_id, s.context_id)
    from card_contexts_orset as s
    where s.user_id = the_user_id
      and s.card_id = the_card_id
      and s.removed_at is null;
perform remove_all_contexts_from_card(the_user_id, the_card_id);
return new_card_id;
end;
$$ language plpgsql;



create or replace function edit_card_progress(the_user_id integer, the_card_id uuid, new_due_date date, new_packed_progress_data bigint) returns void as $$
begin
perform remove_card(the_user_id, the_card_id);
perform add_card(the_user_id, the_card_id, new_due_date, new_packed_progress_data);
end;
$$ language plpgsql;



create or replace function get_cards_orset(the_user_id integer) returns setof cards_orset as $$
begin
return query
select * from cards_orset as s
where s.user_id = the_user_id
    and s.removed_at is null;
end;
$$ language plpgsql;




create or replace function pack_progress_data(
        easiness_factor real,
        prev_interval integer,
        prev_response integer,
        num_of_lapses integer,
        prev_response_was_made_in_mobile_app boolean,
        more_than_one_removed_at boolean,
        prev_seconds_spent_on_card integer
        )
    returns bigint as $$
declare
    ef       bit(12)  := ((easiness_factor - 1) * 512)::integer::bit(12);
    pri      bit(14)  := prev_interval::bit(14);
    prr      bit(3)   := prev_response::bit(3);
    nol      bit(6)   := num_of_lapses::bit(6);
    mobile   bit(1)   := prev_response_was_made_in_mobile_app::integer::bit(1);
    multrem  bit(1)   := more_than_one_removed_at::integer::bit(1);
    prs      bit(15)  := prev_seconds_spent_on_card::bit(15);
    padding  bit(12)  := 0::bit(12);
begin
return (ef || pri || prr || nol || mobile || multrem || prs || padding)::bit(64)::bigint;
end;
$$ language plpgsql;


create or replace function unpack_progress_data(
        in packed_bigint bigint,
        out easiness_factor real,
        out prev_interval integer,
        out prev_response integer,
        out num_of_lapses integer,
        out prev_response_was_made_in_mobile_app boolean,
        out more_than_one_removed_at boolean,
        out prev_seconds_spent_on_card integer
        )
    as $$
declare
    b        bit(64)  := packed_bigint::bit(64);
    ef       bit(12)  := ( b        )::bit(12);
    pri      bit(14)  := ( b <<  12 )::bit(14);   -- 12 = 12
    prr      bit(3)   := ( b <<  26 )::bit(3);    -- 26 = 12+14
    nol      bit(6)   := ( b <<  29 )::bit(6);    -- 29 = 12+14+3
    mobile   bit(1)   := ( b <<  35 )::bit(1);    -- 35 = 12+14+3+6
    multrem  bit(1)   := ( b <<  36 )::bit(1);    -- 36 = 12+14+3+6+1
    prs      bit(15)  := ( b <<  37 )::bit(15);   -- 37 = 12+14+3+6+1+1
-- padding  bit(14)
begin
    easiness_factor := 1.0 + ef::integer::real/512;
    prev_interval := pri::integer;
    prev_response := prr::integer;
    num_of_lapses := nol::integer;
    prev_response_was_made_in_mobile_app := mobile::integer::boolean;
    more_than_one_removed_at := multrem::integer::boolean;
    prev_seconds_spent_on_card := prs::integer;
end;
$$ language plpgsql;



create or replace function get_or_create_deck_id(the_name text) returns uuid as $$
declare
    new_id uuid;
begin
if the_name = ''::text then
   return uuid_nil();
else
insert into decks(name)
    values(the_name)
    on conflict (name) do nothing;     -- sadly, when we do returning id into new_id, it returns null on conflicts
select id into new_id from decks as d where d.name = the_name;
return new_id;
end if;
end;
$$ language plpgsql;



create or replace function get_deck_name(the_deck_id uuid) returns text as $$
declare
    the_name text;
begin
select d.name into the_name from decks as d where d.id = the_deck_id;
return the_name;
end;
$$ language plpgsql;




create or replace function deck_has_card(the_user_id integer, the_card_id uuid, the_deck_id uuid) returns boolean as $$
begin
return exists(
    select 1 from card_decks_orset as s
    where s.user_id = the_user_id
        and s.card_id = the_card_id
        and s.deck_id = the_deck_id
        and s.removed_at is null
        );
end;
$$ language plpgsql;



create or replace function get_card_decks(the_user_id integer, the_card_id uuid) returns table(deck_id uuid) as $$
begin
return query
select s.deck_id from card_decks_orset as s
where s.user_id = the_user_id
    and s.card_id = the_card_id
    and s.removed_at is null;
end;
$$ language plpgsql;



create or replace function get_cards_in_deck(the_user_id integer, the_deck_id uuid) returns table(card_id uuid) as $$
begin
return query
select s.card_id from card_decks_orset as s
where s.user_id = the_user_id
    and s.deck_id = the_deck_id
    and s.removed_at is null;
end;
$$ language plpgsql;


create or replace function add_card_to_deck(the_user_id integer, the_card_id uuid, the_deck_id uuid) returns void as $$
begin
if not deck_has_card(the_user_id, the_card_id, the_deck_id) then
insert into card_decks_orset(user_id, card_id, deck_id)
    values(the_user_id, the_card_id, the_deck_id);
end if;
end;
$$ language plpgsql;



create or replace function remove_card_from_deck(the_user_id integer, the_card_id uuid, the_deck_id uuid) returns void as $$
begin
update card_decks_orset as s set removed_at = now()
where s.user_id = the_user_id
    and s.card_id = the_card_id
    and s.deck_id = the_deck_id
    and s.removed_at is null;
end;
$$ language plpgsql;



create or replace function get_or_create_context_id(the_url text) returns uuid as $$
declare
    new_id uuid;
begin
insert into contexts(url)
    values(the_url)
    on conflict (url) do nothing;
select id into new_id from contexts as ctx where ctx.url = the_url;
return new_id;
end;
$$ language plpgsql;



create or replace function get_context_url(the_context_id uuid) returns text as $$
declare
    the_url text;
begin
select ctx.url into the_url from contexts as ctx where ctx.id = the_context_id;
return the_url;
end;
$$ language plpgsql;



create or replace function get_card_contexts(the_user_id integer, the_card_id uuid) returns table(context_id uuid) as $$
begin
return query
select s.context_id from card_contexts_orset as s
where s.user_id = the_user_id
    and s.card_id = the_card_id
    and s.removed_at is null;
end;
$$ language plpgsql;



create or replace function card_has_context(the_user_id integer, the_card_id uuid, the_context_id uuid) returns boolean as $$
begin
return exists(
    select 1 from card_contexts_orset as s
    where s.user_id = the_user_id
        and s.card_id = the_card_id
        and s.context_id = the_context_id
        and s.removed_at is null
        );
end;
$$ language plpgsql;



create or replace function add_context_to_card(the_user_id integer, the_card_id uuid, the_context_id uuid) returns void as $$
begin
if not card_has_context(the_user_id, the_card_id, the_context_id) then
insert into card_contexts_orset(user_id, card_id, context_id)
    values(the_user_id, the_card_id, the_context_id);
end if;
end;
$$ language plpgsql;



create or replace function remove_context_from_card(the_user_id integer, the_card_id uuid, the_context_id uuid) returns void as $$
begin
update card_contexts_orset as s set removed_at = now()
where s.user_id = the_user_id
    and s.card_id = the_card_id
    and s.context_id = the_context_id
    and s.removed_at is null;
end;
$$ language plpgsql;




------------------------------------------------------------


create or replace function create_and_add_card(the_user_id integer, the_prev_revision_id uuid, new_front text, new_back text, new_due_date date, new_packed_progress_data bigint, new_deck_id uuid, new_context_id uuid) returns uuid as $$
declare
    new_card_id uuid;
begin
if has_card_with_front(the_user_id, new_front) then
    raise exception 'user_id=% already has card with front=%', the_user_id, new_front;
end if;
select * into new_card_id from create_card(the_user_id, the_prev_revision_id, new_front, new_back);
perform add_card(the_user_id, new_card_id, new_due_date, new_packed_progress_data);
perform add_card_to_deck(the_user_id, new_card_id, new_deck_id);
perform add_context_to_card(the_user_id, new_card_id, new_context_id);
return new_card_id;
end;
$$ language plpgsql;




create or replace function tmp_create_and_add_card(the_user_id integer, the_prev_revision_id uuid, new_front text, new_back text, new_due_date date, deck_name text, context_url text) returns uuid as $$
select create_and_add_card(the_user_id, the_prev_revision_id, new_front, new_back,
        new_due_date,
        pack_progress_data(2.5, 0, 0, 0, false, false, 0),
        get_or_create_deck_id(deck_name),
        get_or_create_context_id(context_url));
$$ language sql;



create or replace function response_string_to_integer(the_response text) returns integer as $$
declare
    r integer;
begin
case the_response
    when 'again'      then r := 0;
    when 'hard'       then r := 3;
    when 'normal'     then r := 4;
    when 'easy'       then r := 5;
end case;
return r;
end;
$$ language plpgsql;



create or replace function response_integer_to_string(the_response integer) returns text as $$
declare
    r text;
begin
case the_response
    when 0 then r := 'again';
    when 3 then r := 'hard';
    when 4 then r := 'normal';
    when 5 then r := 'easy';
end case;
return r;
end;
$$ language plpgsql;



create or replace function review_card(the_user_id integer, the_card_id uuid, the_response integer) returns void as $$
declare
    the_due_date date;
    the_packed_progress_data bigint;
    unpacked record;
    new_easiness_factor real;
    new_num_of_lapses integer;
    new_due_date date;
    days_passed_since_repeat integer;
    new_interval integer;
    correction real;
    new_packed_progress_data bigint;
begin
select due_date, packed_progress_data into the_due_date, the_packed_progress_data
from cards_orset as s
where s.user_id = the_user_id
    and s.card_id = the_card_id
    and s.removed_at is null;
select * into unpacked from unpack_progress_data(the_packed_progress_data);

    new_num_of_lapses := unpacked.num_of_lapses;

    correction := 0;
    if unpacked.prev_interval > 1 then   -- easiness factor isn't touched when you forget a card on first or second review
        case the_response
        when 0 then correction := -0.8;
        when 1 then correction := -0.54;
        when 2 then correction := -0.32;
        when 3 then correction := -0.14;
        when 4 then correction := 0;
        when 5 then correction := 0.1;
        end case;
    end if;
    new_easiness_factor := unpacked.easiness_factor + correction;
    new_easiness_factor := greatest(1.3, new_easiness_factor);  
    new_easiness_factor := least(new_easiness_factor, 8.9);

    days_passed_since_repeat := unpacked.prev_interval + ( now()::date - the_due_date );  

    if the_response < 3 then
        new_interval := 0;
        new_due_date := now()::date;
        if unpacked.prev_interval > 0 then
            new_num_of_lapses := new_num_of_lapses + 1;
        end if;
    else
        if unpacked.prev_interval = 0 then
            new_interval := 1;
        else
            new_interval := greatest( 6, days_passed_since_repeat * new_easiness_factor );
        end if;
        new_due_date := now()::date + new_interval * '1 day'::interval;
    end if;

    if the_response >= 3 and unpacked.prev_interval > 0 and days_passed_since_repeat > 21 then
        new_num_of_lapses := 0;
    end if;

    new_num_of_lapses := least(new_num_of_lapses, 2^6-1);

    new_packed_progress_data := pack_progress_data(
        new_easiness_factor,
        new_interval,
        the_response,
        new_num_of_lapses,
        false,   -- prev_response_was_made_in_mobile_app
        false,   -- more_than_one_removed_at
        0        -- prev_seconds_spent_on_card
        );
    perform edit_card_progress(the_user_id, the_card_id, new_due_date, new_packed_progress_data);
end;
$$ language plpgsql;



create or replace function show_all(the_user_id integer) returns table(
        card_id uuid,
        front text,
        back text,
        decks_list text[],
        contexts_list text[],
        added_at timestamptz,        
        due_date date,
        easiness_factor real,
        prev_interval integer,
        prev_response integer,
        num_of_lapses integer,
        prev_response_was_made_in_mobile_app boolean,
        more_than_one_removed_at boolean,
        prev_seconds_spent_on_card integer
        ) as $$
select
    c.id,
    c.front,
    c.back,
    array(select get_deck_name(deck_id)        from get_card_decks(the_user_id, c.id)),
    array(select get_context_url(context_id)   from get_card_contexts(the_user_id, c.id)),
    s.added_at,
    s.due_date,
    (unpack_progress_data(s.packed_progress_data)).*
from get_cards_orset(the_user_id) as s 
    join cards as c on s.card_id = c.id
where true;
$$ language sql;



create or replace function show_card(the_user_id integer, the_card_id uuid) returns table(
        card_id uuid,
        front text,
        back text,
        decks_list text[],
        contexts_list text[],
        added_at timestamptz,        
        due_date date,
        easiness_factor real,
        prev_interval integer,
        prev_response integer,
        num_of_lapses integer,
        prev_response_was_made_in_mobile_app boolean,
        more_than_one_removed_at boolean,
        prev_seconds_spent_on_card integer
        ) as $$
select
    c.id,
    c.front,
    c.back,
    array(select get_deck_name(deck_id)        from get_card_decks(the_user_id, c.id)),
    array(select get_context_url(context_id)   from get_card_contexts(the_user_id, c.id)),
    s.added_at,
    s.due_date,
    (unpack_progress_data(s.packed_progress_data)).*
from cards as c join cards_orset as s on c.id = s.card_id
where c.id = the_card_id
    and s.removed_at is null;
$$ language sql;



commit;


