CREATE TABLE `packets` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`room` text NOT NULL,
	`generation` integer NOT NULL,
	`sender` integer NOT NULL,
	`sequence` integer NOT NULL,
	`channel` integer NOT NULL,
	`mode` integer NOT NULL,
	`data` text NOT NULL,
	FOREIGN KEY (`room`) REFERENCES `rooms`(`code`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `packet_identity` ON `packets` (`room`,`generation`,`sender`,`sequence`);--> statement-breakpoint
CREATE INDEX `packet_mailbox` ON `packets` (`room`,`generation`,`sender`,`id`);--> statement-breakpoint
CREATE TABLE `rooms` (
	`code` text PRIMARY KEY NOT NULL,
	`host` text NOT NULL,
	`guest` text,
	`creator` text NOT NULL,
	`expires` integer NOT NULL,
	`generation` integer DEFAULT 0 NOT NULL,
	`instance1` text DEFAULT '' NOT NULL,
	`instance2` text DEFAULT '' NOT NULL,
	`ready1` integer DEFAULT -1 NOT NULL,
	`ready2` integer DEFAULT -1 NOT NULL,
	`seen1` integer DEFAULT 0 NOT NULL,
	`seen2` integer DEFAULT 0 NOT NULL,
	`accepted1` integer DEFAULT 0 NOT NULL,
	`accepted2` integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE INDEX `room_expiry` ON `rooms` (`expires`);