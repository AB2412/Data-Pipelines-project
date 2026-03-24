# JURISDICTIONCompaniesFetcher Bot

## About the data publisher

Describe the source. Specifically:

- Who is behind it?
- What gives it regulatory power (thus justifying it being in
  OpenCorporates)?
- How often is it updated?

## About the data

- The source: https://sosbiz.idaho.gov/
- Site to download: https://sosbiz.idaho.gov/data-requests

## Development

- You can run this bot locally using the command `bundle exec openc_bot rake bot:run FETCHER_BOT_ENV=development` or if you have a data folder, you can run add the `DATA_FOLDER=data/YYYY-MM-DD` env variable to the task to skip the `fetcher` stage.
- The following folders are required to run the bot and they will be automatically generated: `data`, `db` and `tmp`.

  - The tmp folder is designed to store temporary values like the current parsed/transformed record, or to show a failing record i.e. write to tmp if a record raises an error.
  - The data folder represents the main storage point for the source and the processed files. Every file grabbed by the fetcher should be placed here, inside a sub-folder with a naming convention of `YYYY-MM-DD`, value that would ideally represent the date when the registry made the file available, or as a fallback the default would be the first of that month if we can't find the exact day.
  - The db file is used to store databases

## Production

- To run in production, use the following command ` bundle exec openc_bot rake bot:run2 FETCHER_BOT_ENV=production`
