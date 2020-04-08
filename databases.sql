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
  `password` BLOB(60) NOT NULL COMMENT 'bcrypt hash of password with salt',
  PRIMARY KEY (`id`),
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
-- Table `exchangedataset`.`quotaperiods`
-- -----------------------------------------------------
CREATE TABLE `exchangedataset`.`quotaperiods` (
  `key_id` INT UNSIGNED NOT NULL COMMENT 'API key id',
  `start_date` DATETIME NOT NULL,
  `end_date` DATETIME NOT NULL,
  `used` BIGINT UNSIGNED NOT NULL COMMENT 'total used quota using a API key in bytes in a period of time',
  `quota` BIGINT UNSIGNED NOT NULL COMMENT 'quota in bytes for a API key in a period of time',
  `plan` VARCHAR(45) NOT NULL,
  INDEX `fk_used_1_idx` (`key_id` ASC),
  UNIQUE INDEX `key_id_start_date` (`key_id` ASC, `start_date` DESC),
  CONSTRAINT `fk_quotaperiods_key_id`
    FOREIGN KEY (`key_id`)
    REFERENCES `exchangedataset`.`apikeys` (`id`)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT)
ENGINE = InnoDB;


DROP TABLE IF EXISTS `exchangedataset`.`quotaperiods_now`;
CREATE OR REPLACE VIEW `exchangedataset`.`quotaperiods_now` AS
  SELECT * FROM 

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



DROP TABLE IF EXISTS `exchangedataset`.`customer_apikeys`;
CREATE OR REPLACE VIEW `exchangedataset`.`customer_apikeys` AS
  SELECT c.`key` customer_key,
      a.`key` apikey,
      a.enabled
  FROM apikeys a,
        customers c
  WHERE a.customer_id = c.id
;

DROP TABLE IF EXISTS `exchangedataset`.`apikey_quotaperiods`;
CREATE  OR REPLACE VIEW `apikey_quotaperiods` AS
  SELECT a.`key` apikey,
      a.enabled enabled,
      qt.start_date start_date,
      qt.end_date end_date,
      qt.used used,
      qt.quota quota,
      qt.plan plan
  FROM quotaperiods qt,
      apikeys a
  WHERE qt.key_id = a.id
;

DROP TABLE IF EXISTS `exchangedataset`.`apikey_quotaperiods_now`;
CREATE  OR REPLACE VIEW `apikey_quotaperiods_now` AS
  SELECT *
  FROM apikey_quotaperiods aqt
  WHERE aqt.start_date <= NOW() AND NOW() < aqt.end_date
;

-- -----------------------------------------------------
-- procedure increment_apikey_used_now
-- -----------------------------------------------------

USE `exchangedataset`;
DELIMITER $$
DROP FUNCTION `apikey_available`$$
CREATE FUNCTION `apikey_available` (_apikey BINARY(32)) RETURNS INTEGER DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE bool INTEGER;
  SELECT (count(*) AND used < quota) INTO bool
    FROM apikeys a,
        apikey_quotaperiods_now aqtn
    WHERE a.`key` = aqtn.apikey
        AND a.enabled = 1
        AND aqtn.apikey = _apikey
  ;
  RETURN bool;
END$$

DROP PROCEDURE `increment_apikey_used_now`$$
CREATE PROCEDURE `increment_apikey_used_now` (IN _apikey BINARY(32), IN amount BIGINT)
BEGIN
  UPDATE apikey_quotaperiods_now aqtn
    SET aqtn.used = aqtn.used + amount
    WHERE aqtn.apikey = _apikey
  ;
END$$
DELIMITER ;

-- -----------------------------------------------------
-- dataset information for individual gzip file
-- -----------------------------------------------------
DROP SCHEMA `dataset_info` ;
CREATE SCHEMA `dataset_info` ;

USE `dataset_info` ;

-- -----------------------------------------------------
-- Table `dataset_info`.`datasets`
-- -----------------------------------------------------
CREATE TABLE `dataset_info`.`datasets` (
  `filename` VARCHAR(128) NOT NULL,
  `exchange` VARCHAR(64) NOT NULL,
  `start_nanosec` BIGINT UNSIGNED NOT NULL,
  `end_nanosec` BIGINT UNSIGNED NOT NULL,
  `is_start` TINYINT(1) UNSIGNED NOT NULL,
  PRIMARY KEY (`filename`),
  INDEX `index_dataset_info_exchange_start_nanosec` (`exchange` ASC, `start_nanosec` ASC))
ENGINE = InnoDB;

DELIMITER $$

DROP PROCEDURE `find_dataset`$$
CREATE PROCEDURE `find_dataset` (IN _exchange VARCHAR(64), IN minute BIGINT)
BEGIN
  DECLARE nanosec BIGINT;
  SET nanosec = minute * 60 * 1000000000;
  SELECT filename FROM datasets WHERE exchange = _exchange AND nanosec <= start_nanosec AND end_nanosec < nanosec + 60000000000 ORDER BY start_nanosec ASC;
END$$


DROP PROCEDURE `find_dataset_for_snapshot`$$
CREATE PROCEDURE `find_dataset_for_snapshot` (IN _exchange VARCHAR(64), IN minute BIGINT)
BEGIN
  DECLARE nanosec BIGINT DEFAULT minute * 60 * 1000000000;
  DECLARE tenminuteago BIGINT DEFAULT (FLOOR(minute / 10) * 10) * 60 * 1000000000;
  DECLARE start_file_nanosec BIGINT DEFAULT tenminuteago;
  
  SELECT start_nanosec INTO start_file_nanosec
    FROM datasets
    WHERE exchange = _exchange
        AND tenminuteago <= start_nanosec
        AND end_nanosec < nanosec + 60000000000
        AND is_start = 1
    ORDER BY start_nanosec DESC
    LIMIT 1;
  SELECT filename
      FROM datasets
      WHERE exchange = _exchange
      AND start_file_nanosec <= start_nanosec
      AND end_nanosec < nanosec + 60000000000
      ORDER BY start_nanosec ASC;
END$$

DELIMITER ;

CREATE USER 'stream_api'@'%' IDENTIFIED BY '4y7B66oacuT7DEF6UUv2zs6LK' REQUIRE SSL;
GRANT EXECUTE ON FUNCTION `exchangedataset`.`apikey_available` TO 'stream_api'@'%';
GRANT EXECUTE ON PROCEDURE `exchangedataset`.`increment_apikey_used_now` TO 'stream_api'@'%';
GRANT EXECUTE ON PROCEDURE `dataset_info`.`find_dataset` TO 'stream_api'@'%';
GRANT EXECUTE ON PROCEDURE `dataset_info`.`find_dataset_for_snapshot` TO 'stream_api'@'%';

CREATE USER 'dump'@'172.31.1.191' IDENTIFIED BY 'cRlHwzM7c6GYV0LiVn0g5CNVL' REQUIRE SSL;
GRANT SELECT, INSERT ON TABLE `dataset_info`.`datasets` TO 'dump'@'172.31.1.191';


-- CREATE USER 'web_api'@'';

