-- -----------------------------------------------------
-- database for api keys and customer information
-- -----------------------------------------------------
DROP SCHEMA `exchangedataset` ;
CREATE SCHEMA `exchangedataset` ;

USE `exchangedataset` ;

-- -----------------------------------------------------
-- Table `exchangedataset`.`customers`
-- -----------------------------------------------------
CREATE TABLE `exchangedataset`.`customers` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'customer unique id used internally',
  `key` BIGINT UNSIGNED NOT NULL COMMENT 'customer specific unique random value used as id externally',
  `email` VARCHAR(256) NOT NULL COMMENT 'primary email for communicatin to a costomer',
  `password` CHAR(60) BINARY NOT NULL COMMENT 'bcrypt hash of password with salt',
  PRIMARY KEY (`id`),
  UNIQUE INDEX `key_UNIQUE` (`key` ASC),
  UNIQUE INDEX `email_UNIQUE` (`email` ASC)
)
ENGINE = InnoDB;

-- -----------------------------------------------------
-- Table `exchangedataset`.`apikeys`
-- -----------------------------------------------------
CREATE TABLE `exchangedataset`.`apikeys` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'unique ID to distinguish every API key',
  `key` BINARY(32) NOT NULL COMMENT 'API key itself in 256bit binary',
  `customer_id` INT UNSIGNED NULL COMMENT 'customer id of customer whose API key is for',
  `enabled` TINYINT NOT NULL COMMENT 'bool value, 0 for key disabled and should not be used, 1 for enabled',
  PRIMARY KEY (`id`),
  UNIQUE INDEX `key_UNIQUE` (`key` ASC),
  INDEX `index_fk_apikeys_customer_id` (`customer_id` ASC),
  CONSTRAINT `fk_apikeys_customer_id`
    FOREIGN KEY (`customer_id`)
    REFERENCES `exchangedataset`.`customers` (`id`)
    ON DELETE SET NULL
    ON UPDATE SET NULL)
ENGINE = InnoDB
COMMENT = 'table to store api keys';

-- -----------------------------------------------------
-- Table `exchangedataset`.`tickets`
-- -----------------------------------------------------
CREATE TABLE `exchangedataset`.`tickets` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'unique id to distinguish ticket',
  `key` BIGINT UNSIGNED NOT NULL COMMENT 'unique key for this ticket used externally',
  `key_id` INT UNSIGNED NOT NULL COMMENT 'API key id',
  `start_date` DATETIME NOT NULL,
  `end_date` DATETIME NOT NULL,
  `used` BIGINT UNSIGNED NOT NULL COMMENT 'total used quota',
  `quota` BIGINT UNSIGNED NOT NULL COMMENT 'quota in bytes',
  PRIMARY KEY (`id`),
  UNIQUE INDEX `key_UNIQUE` (`key_id`, `key`),
  INDEX `fk_used_1_idx` (`key_id` ASC),
  CONSTRAINT `fk_tickets_key_id`
    FOREIGN KEY (`key_id`)
    REFERENCES `exchangedataset`.`apikeys` (`id`)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `exchangedataset`.`purchases`
-- -----------------------------------------------------
CREATE TABLE `exchangedataset`.`purchases` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `customer_id` INT UNSIGNED NULL,
  `date` DATETIME NOT NULL,
  `item` VARCHAR(256) NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `index_fk_purchases_customer_id` (`customer_id` ASC),
  CONSTRAINT `fk_purchases_customer_id`
    FOREIGN KEY (`customer_id`)
    REFERENCES `exchangedataset`.`customers` (`id`)
    ON DELETE SET NULL
    ON UPDATE SET NULL)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- procedure
-- -----------------------------------------------------

USE `exchangedataset`;
DELIMITER $$

DROP PROCEDURE `unregister_customer`$$
CREATE PROCEDURE `unregister_customer` (IN _key BIGINT UNSIGNED)
BEGIN
  DELETE FROM customers WHERE `key` = _key;
END$$

DROP PROCEDURE `search_customer_apikey`$$
CREATE PROCEDURE `search_customer_apikey` (IN _apikey VARBINARY(32))
BEGIN
  SELECT c.`key` `key`,
        c.email email,
        a.`key` apikey
    FROM apikeys a,
        customers c
    WHERE a.customer_id = c.id
        AND a.`key` LIKE BINARY CONCAT(_apikey, "%")
  ;
END$$

DROP PROCEDURE `search_customer_email`$$
CREATE PROCEDURE `search_customer_email` (IN _email VARCHAR(256))
BEGIN
  SELECT c.`key` `key`,
        c.email email
    FROM customers c
    WHERE c.email LIKE CONCAT(_email, "%")
  ;
END$$

DROP PROCEDURE `register_new_customer`$$
CREATE PROCEDURE `register_new_customer` (
  IN _key BIGINT UNSIGNED,
  IN _email VARCHAR(256),
  IN _password BLOB(60)
)
BEGIN
  INSERT INTO customers
        (`id`, `key`, `email`, `password`)
    VALUES
        (NULL, _key, _email, _password)
  ;
END$$

DROP PROCEDURE `get_customer_credential`$$
CREATE PROCEDURE `get_customer_credential` (
  IN _email VARCHAR(256)
)
BEGIN
  SELECT `key`,
        `password`
    FROM customers
    WHERE `email` = _email
  ;
END$$



DROP PROCEDURE `remove_apikey`$$
CREATE PROCEDURE `remove_apikey` (IN _apikey BINARY(32))
BEGIN
  DELETE FROM apikeys WHERE `key` = _apikey;
END$$

DROP PROCEDURE `list_apikeys`$$
CREATE PROCEDURE `list_apikeys` (IN _customer_key BIGINT UNSIGNED)
BEGIN
  SELECT `key`, `enabled`
    FROM apikeys
    WHERE `customer_id` = (SELECT `id` FROM customers WHERE `key` = _customer_key)
  ;
END$$

DROP PROCEDURE `create_new_apikey`$$
CREATE PROCEDURE `create_new_apikey` (
  IN _key BINARY(32),
  IN _customer_key BIGINT UNSIGNED,
  IN _enabled INT
)
BEGIN
  INSERT INTO apikeys
        (`id`, `key`, `customer_id`, `enabled`)
    VALUES
        (NULL, _key, (SELECT `id` FROM customers WHERE `key` = _customer_key), _enabled)
  ;
END$$

DROP PROCEDURE `set_apikey_enabled`$$
CREATE PROCEDURE `set_apikey_enabled` (IN _apikey BINARY(32), IN _enabled TINYINT)
BEGIN
  UPDATE apikeys
    SET `enabled` = _enabled
    WHERE `key` = _apikey
  ;
END$$

DROP FUNCTION `get_apikey_customer_key`$$
CREATE FUNCTION `get_apikey_customer_key` (_apikey BINARY(32)) RETURNS BIGINT UNSIGNED DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE _customer_key BIGINT UNSIGNED;
  SELECT c.`key` INTO _customer_key
    FROM customers c,
        apikeys a
    WHERE c.`id` = a.`customer_id`
        AND a.`key` = _apikey
  ;
  RETURN _customer_key;
END$$


DROP PROCEDURE `remove_ticket`$$
CREATE PROCEDURE `remove_ticket` (IN _apikey BINARY(32), IN _key BIGINT UNSIGNED)
BEGIN
  DELETE FROM tickets
    WHERE `key_id` = (SELECT `id` FROM apikeys WHERE `key` = _apikey)
        AND `key` = _key
  ;
END$$

DROP PROCEDURE `list_apikey_tickets`$$
CREATE PROCEDURE `list_apikey_tickets` (IN _apikey BINARY(32))
BEGIN
  SELECT * FROM tickets
    WHERE `key_id` = (SELECT `id` FROM apikeys WHERE `key` = _apikey)
  ;
END$$

DROP PROCEDURE `create_new_ticket`$$
CREATE PROCEDURE `create_new_ticket` (
  IN _apikey BINARY(32),
  IN _ticket_key BIGINT UNSIGNED,
  IN _start_date DATETIME,
  IN _end_date DATETIME,
  IN _used BIGINT UNSIGNED,
  IN _quota BIGINT UNSIGNED
)
BEGIN
  INSERT INTO tickets
        (`id`, `key`, `key_id`, `start_date`, `end_date`, `used`, `quota`)
    VALUES
        (NULL, _ticket_key, (SELECT `id` FROM apikeys WHERE `key` = _apikey), _start_date, _end_date, _used, _quota)
  ;
END$$

DROP FUNCTION `apikey_available`$$
CREATE FUNCTION `apikey_available` (_apikey BINARY(32)) RETURNS INTEGER DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE bool INTEGER;
  SELECT count(*) > 0 INTO bool
    FROM apikeys a,
        tickets t
    WHERE a.`id` = t.key_id
        AND a.`key` = _apikey
        AND a.enabled = 1
        AND t.start_date <= NOW() AND NOW() < t.end_date
        AND t.used < quota
  ;
  RETURN bool;
END$$

DROP PROCEDURE `increment_apikey_used_now`$$
CREATE PROCEDURE `increment_apikey_used_now` (IN _apikey BINARY(32), IN amount BIGINT)
BEGIN
  DECLARE _key_id INT UNSIGNED;
  SELECT `id` INTO _key_id FROM apikeys WHERE `key` = _apikey;
  UPDATE tickets t
    SET t.used = t.used + amount
    WHERE t.key_id = _key_id
        AND t.start_date <= NOW() AND NOW() < t.end_date
        AND t.used < quota
    ORDER BY t.end_date ASC
    LIMIT 1
  ;
END$$
DELIMITER ;

CREATE USER 'accountapi'@'%' IDENTIFIED BY 'Yh9JqmUxzRqtEyedohJ0cvyLFfmWMb' REQUIRE SSL;
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`create_new_apikey` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`list_apikeys` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`set_apikey_enabled` TO 'accountapi'@'%';
GRANT EXECUTE ON FUNCTION `exchangedataset`.`get_apikey_customer_key` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`remove_apikey` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`register_new_customer` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`unregister_customer` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`get_customer_credential` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`search_customer_apikey` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`search_customer_email` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`create_new_ticket` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`list_apikey_tickets` TO 'accountapi'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`remove_ticket` TO 'accountapi'@'%';

CREATE USER 'stream_api'@'%' IDENTIFIED BY '4y7B66oacuT7DEF6UUv2zs6LK' REQUIRE SSL;
GRANT EXECUTE ON FUNCTION `exchangedataset`.`apikey_available` TO 'stream_api'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`increment_apikey_used_now` TO 'stream_api'@'%';
GRANT EXECUTE ON PROCEDURE `dataset_info`.`find_dataset` TO 'stream_api'@'%';
GRANT EXECUTE ON PROCEDURE `dataset_info`.`find_dataset_for_snapshot` TO 'stream_api'@'%';

CREATE USER 'dump'@'%' IDENTIFIED BY 'cRlHwzM7c6GYV0LiVn0g5CNVL' REQUIRE SSL;
GRANT SELECT, INSERT ON TABLE `dataset_info`.`datasets` TO 'dump'@'%';


-- CREATE USER 'web_api'@'';

