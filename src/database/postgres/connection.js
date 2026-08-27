'use strict';

const fs = require('fs');
const nconf = require('nconf');
const winston = require('winston');
const _ = require('lodash');

const connection = module.exports;

connection.getConnectionOptions = function (postgres) {
	postgres = postgres || nconf.get('postgres');
	// Sensible defaults for PostgreSQL, if not set
	if (!postgres.host) {
		postgres.host = '127.0.0.1';
	}
	if (!postgres.port) {
		postgres.port = 5432;
	}
	const dbName = postgres.database;
	if (dbName === undefined || dbName === '') {
		winston.warn('You have no database name, using "nodebb"');
		postgres.database = 'nodebb';
	}
	if (!postgres.schema) {
		postgres.schema = process.env.NODEBB_POSTGRES_SCHEMA || 'public';
	}
	if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(postgres.schema)) {
		throw new Error(`Invalid postgres:schema value: ${postgres.schema}`);
	}

	const connOptions = {
		host: postgres.host,
		port: postgres.port,
		user: postgres.username,
		password: postgres.password,
		database: postgres.database,
		schema: postgres.schema, // Not used by Postgres to set the schema, only there to be re-used elsewhere in the postgres adapter
		options: `-c search_path=${postgres.schema}`, // Set the schema to use, redundant with the onConnect callback but not conflicting
		ssl: String(postgres.ssl) === 'true',
		max: 2,
		connectionTimeoutMillis: 90000,
	};

	if (typeof postgres.ssl === 'object' && !Array.isArray(postgres.ssl) && postgres.ssl !== null) {
		const { ssl } = postgres;
		connOptions.ssl = {
			rejectUnauthorized: ssl.rejectUnauthorized,
		};
		['ca', 'key', 'cert'].forEach((prop) => {
			if (ssl.hasOwnProperty(prop)) {
				connOptions.ssl[prop] = fs.readFileSync(ssl[prop]).toString();
			}
		});
	}

	return _.merge(connOptions, postgres.options || {});
};

connection.connect = async function (options) {
	const { Pool } = require('pg');
	const connOptions = connection.getConnectionOptions(options);
	connOptions.onConnect = async (client) => {
		await client.query(`SET search_path TO "${connOptions.schema}"`); // Set the search path for which schema to use on every new connection to the pool
	};
	const db = new Pool(connOptions);
	await db.connect();
	return db;
};

require('../../promisify')(connection);
