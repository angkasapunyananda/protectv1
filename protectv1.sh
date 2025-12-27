#!/bin/bash

REMOTE_PATH="/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"
TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

echo "🚀 Memasang proteksi Anti Delete Server..."

if [ -f "$REMOTE_PATH" ]; then
  mv "$REMOTE_PATH" "$BACKUP_PATH"
  echo "📦 Backup file lama dibuat di $BACKUP_PATH"
fi

mkdir -p "$(dirname "$REMOTE_PATH")"
chmod 755 "$(dirname "$REMOTE_PATH")"

cat > "$REMOTE_PATH" << 'EOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Http\Response;
use Pterodactyl\Models\Server;
use Illuminate\Support\Facades\Log;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class ServerDeletionService
{
    protected bool $force = false;

    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository,
        private DatabaseManagementService $databaseManagementService
    ) {
    }

    public function withForce(bool $bool = true): self
    {
        $this->force = $bool;
        return $this;
    }

    public function handle(Server $server): void
    {
        $user = Auth::user();

        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id
                    ?? $server->user_id
                    ?? ($server->owner?->id ?? null)
                    ?? ($server->user?->id ?? null);

                if ($ownerId === null) {
                    throw new DisplayException('𝙰𝙺𝚂𝙴𝚂 𝙳𝙸 𝚃𝙾𝙻𝙰𝙺: 𝙸𝙽𝙵𝙾𝚁𝙼𝙰𝚂𝙸 𝙿𝙴𝙼𝙸𝙻𝙸𝙺 𝚂𝙴𝚁𝚅𝙴𝚁 𝚃𝙸𝙳𝙰𝙺 𝚃𝙴𝚁𝙳𝙴𝚃𝙴𝙺𝚂𝙸.');
                }

                if ($ownerId !== $user->id) {
                    throw new DisplayException('𝙰𝙺𝚂𝙴𝚂 𝙳𝙸 𝚃𝙾𝙻𝙰𝙺. 𝙻𝚄 𝚂𝙸𝙰𝙿𝙰 𝙺𝙰𝙲𝚄𝙽𝙶? 𝙻𝚄 𝙲𝚄𝙼𝙰 𝙱𝙸𝚂𝙰 𝙷𝙰𝙿𝚄𝚂 𝚂𝙴𝚁𝚅𝙴𝚁 𝙻𝚄 𝚂𝙴𝙽𝙳𝙸𝚁𝙸. 𝙰𝙽𝙶𝙺𝙰𝚂𝙰 𝙿𝚁𝙾𝚃𝙴𝙲𝚃 𝙰𝙲𝚃𝙸𝚅𝙴 ');
                }
            }
        }

        try {
            $this->daemonServerRepository->setServer($server)->delete();
        } catch (DaemonConnectionException $exception) {
            if (!$this->force && $exception->getStatusCode() !== Response::HTTP_NOT_FOUND) {
                throw $exception;
            }

            Log::warning($exception);
        }

        $this->connection->transaction(function () use ($server) {
            foreach ($server->databases as $database) {
                try {
                    $this->databaseManagementService->delete($database);
                } catch (\Exception $exception) {
                    if (!$this->force) {
                        throw $exception;
                    }

                    $database->delete();
                    Log::warning($exception);
                }
            }

            $server->delete();
        });
    }
}
EOF

chmod 644 "$REMOTE_PATH"

echo "✅ Proteksi Anti Delete Server berhasil dipasang!"
echo "📂 Lokasi file: $REMOTE_PATH"
echo "🗂️ Backup file lama: $BACKUP_PATH (jika sebelumnya ada)"
echo "🔒 Hanya Admin (ID 1) yang bisa hapus server lain."
