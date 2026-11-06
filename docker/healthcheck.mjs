// 容器健康检查脚本
//
// 用法：node /app/healthcheck.mjs <web|online>
//
// web    校验静态页面可访问，并且文件接口（浏览器端存档/扩展导入依赖）返回正常
// online 校验联机服务（WebSocket 大厅）端口可连接
//
// 健康时退出码 0，异常时退出码 1，由 Docker 记录到容器健康状态中。

import net from "node:net";

const role = process.argv[2] ?? "web";
const TIMEOUT_MS = 5000;

function fail(message) {
	console.error(`[healthcheck] ${message}`);
	process.exit(1);
}

function request(url) {
	return fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
}

async function checkWeb() {
	const port = Number(process.env.NONAME_WEB_PORT ?? 8089);
	const base = `http://127.0.0.1:${port}`;

	let index;
	try {
		index = await request(`${base}/index.html`);
	} catch (error) {
		fail(`网页服务不可访问：${error}`);
	}
	if (!index.ok) {
		fail(`/index.html 返回 HTTP ${index.status}`);
	}

	let probe;
	try {
		probe = await request(`${base}/checkFile?fileName=noname.js`);
	} catch (error) {
		fail(`文件接口不可访问：${error}`);
	}
	const result = await probe.json().catch(() => null);
	if (!result?.success || result.data !== "file") {
		fail(`文件接口返回异常：${JSON.stringify(result)}`);
	}
}

async function checkOnline() {
	const port = Number(process.env.NONAME_ONLINE_PORT ?? 8082);
	await new Promise((resolve, reject) => {
		const socket = net.connect({ port, host: "127.0.0.1" });
		socket.setTimeout(TIMEOUT_MS, () => socket.destroy(new Error("连接超时")));
		socket.once("connect", () => {
			socket.end();
			resolve();
		});
		socket.once("error", reject);
	}).catch(error => fail(`联机服务不可连接：${error.message}`));
}

switch (role) {
	case "web":
		await checkWeb();
		break;
	case "online":
		await checkOnline();
		break;
	default:
		fail(`未知的检查目标：${role}`);
}

process.exit(0);
