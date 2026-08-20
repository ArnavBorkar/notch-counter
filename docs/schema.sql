-- The app creates these automatically on first connect (see Database.bootstrap).
-- Kept here so you can read the shape without launching anything.

create table if not exists nc_users (
    id         uuid primary key default gen_random_uuid(),
    email      text unique not null,
    name       text not null,
    pin_hash   text not null,          -- sha256(salt || pin)
    pin_salt   text not null,
    created_at timestamptz not null default now()
);

create table if not exists nc_tasks (
    id          uuid primary key default gen_random_uuid(),
    title       text not null,
    status      text not null default 'backlog',   -- backlog | doing | done
    important   boolean not null default false,
    assignee_id uuid references nc_users(id) on delete set null,
    position    double precision not null default 0,
    created_by  uuid references nc_users(id) on delete set null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

create table if not exists nc_outreach (
    user_id uuid not null references nc_users(id) on delete cascade,
    day     date not null default current_date,
    count   integer not null default 0,
    primary key (user_id, day)
);
