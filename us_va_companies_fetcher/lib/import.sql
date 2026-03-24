.mode csv
.headers on
.separator ,
.import BT.csv BT
.import PSA.csv PSA
.import GP.csv GP
.import NameHistory.csv NameHistory
.import Officer.csv Officer
.import ReservedName.csv ReservedName
.import Merger.csv Merger
.import Amendment.csv Amendment
.import LP.csv LP
.import LLC.csv LLC
.import Corp.csv Corp
CREATE INDEX idx0 on Corp(EntityID);
CREATE INDEX idx1 on LP(EntityID);
CREATE INDEX idx2 on LLC(EntityID);
CREATE INDEX idx3 on Officer(EntityID);
CREATE INDEX idx4 on NameHistory(EntityID);
CREATE INDEX idx5 on Amendment(EntityID);
CREATE INDEX idx6 on Merger(EntityID);
