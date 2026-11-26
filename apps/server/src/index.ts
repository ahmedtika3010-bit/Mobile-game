import { assertConfig, config } from './config';
import { startServer } from './server';

assertConfig();
startServer(config.port).then(({ port }) => {
  console.log(`${config.appName} server listening on :${port}${config.devAuth ? ' (DEV_AUTH enabled)' : ''}`);
});
