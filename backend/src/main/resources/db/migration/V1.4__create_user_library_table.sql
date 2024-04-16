DROP TABLE IF EXISTS user_library;

CREATE TABLE user_library(
    user_id uuid NOT NULL,
    movie_id integer NOT NULL,
    start_watch_time int NOT NULL DEFAULT 0,
    added_time timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user_location text,
    FOREIGN KEY (user_id) REFERENCES user_account(id),
    FOREIGN KEY (movie_id) REFERENCES movie(id),
    PRIMARY KEY (user_id, movie_id)
);
