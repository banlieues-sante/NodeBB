#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const env = process.env;

function bool(v, def = false) {
	if (v === undefined || v === '') return def;
	return v === 'true' || v === '1';
}

function required(name) {
	if (!env[name]) {
		console.error(`[render-config] Missing required environment variable: ${name}`);
		process.exit(1);
	}
	return env[name];
}

const config = {
	url: required('NODEBB_URL'),
	secret: required('NODEBB_SECRET'),
	database: env.NODEBB_DATABASE || 'postgres',
	port: parseInt(env.NODEBB_PORT || '4567', 10),
	trust_proxy: true,
	postgres: {
		host: required('NODEBB_POSTGRES_HOST'),
		port: parseInt(env.NODEBB_POSTGRES_PORT || '5432', 10),
		username: required('NODEBB_POSTGRES_USERNAME'),
		password: required('NODEBB_POSTGRES_PASSWORD'),
		database: env.NODEBB_POSTGRES_DATABASE || 'postgres',
		schema: env.NODEBB_POSTGRES_SCHEMA || 'public',
	},
};

if (bool(env.NODEBB_POSTGRES_SSL)) {
	config.postgres.ssl = {
		rejectUnauthorized: bool(env.NODEBB_POSTGRES_SSL_REJECT_UNAUTHORIZED, true),
	};
}

if (env.NODEBB_ADMIN_USERNAME) {
	config['admin:username'] = required('NODEBB_ADMIN_USERNAME');
	config['admin:password'] = required('NODEBB_ADMIN_PASSWORD');
	config['admin:password:confirm'] = required('NODEBB_ADMIN_PASSWORD');
	config['admin:email'] = required('NODEBB_ADMIN_EMAIL');
}

const outPath = env.NODEBB_CONFIG_PATH || '/opt/config/config.json';
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(config, null, 4));
console.log(`[render-config] Wrote config to ${outPath}`);