DROP TABLE IF EXISTS user_account CASCADE;

CREATE TABLE user_account(
    id uuid PRIMARY KEY,
    email text NOT NULL,
    password text NOT NULL,
    full_name text NOT NULL,
    user_location text
);
