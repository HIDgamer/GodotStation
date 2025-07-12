<script lang="ts">
	import { HandHeart, Info } from 'phosphor-svelte';
	import '../app.css';
	import { fade, scale } from 'svelte/transition';
	import { backOut, quintOut } from 'svelte/easing';
	import { postMessage } from '$lib/utils';

	let { children } = $props();

	let innerWidth = $state(0);
	let innerHeight = $state(0);

	const getZoomScale = (width: number, height: number) => {
		const baseWidth = 1280;
		const baseHeight = 720;

		const scaleX = width / baseWidth;
		const scaleY = height / baseHeight;
		const scale = Math.min(scaleX, scaleY);

		return scale;
	};
	const zoomScale = $derived(getZoomScale(innerWidth, innerHeight));

	const credits = [
		{
			role: 'Body and hair 3D models',
			name: 'The Observatory',
			license: 'Non-commercial usage',
			url: 'https://www.youtube.com/@TheObservatoryShow'
		},
		{
			role: 'Clothes, textures, and animation',
			name: 'EggSupernova',
			url: 'https://github.com/kuroki100'
		},
		{
			role: 'UI and programming',
			name: 'DoceAzedo',
			url: 'https://github.com/doceazedo'
		}
	];

	let openCreditsDialog = $state(false);
</script>

<svelte:window bind:innerWidth bind:innerHeight oncontextmenu={(e) => e.preventDefault()} />

<div class="flex h-[720px] w-[1280px]" style="transform: scale({zoomScale});">
	{@render children()}

	<button
		class="group absolute bottom-5 left-4 flex size-12 items-center justify-center rounded-full bg-cyan-50 text-cyan-700/40 transition-all hover:scale-105"
		onclick={() => (openCreditsDialog = true)}
	>
		<HandHeart size={24} weight="bold" />
		<span
			class="absolute -bottom-3 z-20 w-[max-content] rounded-lg bg-cyan-700 px-1.5 py-px text-sm font-extrabold text-cyan-50 transition-all group-hover:rotate-2"
		>
			Credits
		</span>
	</button>
</div>

{#if openCreditsDialog}
	<div
		class="absolute top-0 left-0 z-20 flex size-full items-center justify-center bg-cyan-950/50"
		style="transform: scale({zoomScale});"
		transition:fade={{ duration: 300, easing: quintOut }}
	>
		<div
			class="relative flex w-[32rem] flex-col items-center gap-5 rounded-4xl bg-cyan-50 px-7 pt-12 pb-7 text-xl"
			transition:scale={{ duration: 300, start: 0.5, easing: backOut }}
		>
			<h1
				class="absolute -top-7 rounded-[1.2rem] bg-cyan-950 px-10 py-3 text-2xl font-extrabold text-white"
			>
				Godot WRY DEMO
			</h1>
			<ul class="flex w-full flex-col gap-5 text-cyan-950">
				{#each credits as credit}
					<li>
						<p class="text-2xl font-bold">{credit.role}</p>
						<button
							onclick={() => postMessage('open_url', { url: credit.url })}
							class="-mt-1 text-cyan-950/80 hover:underline"
						>
							{credit.name}
						</button>
						{#if credit.license}
							<p class="-mt-0.5 flex items-center gap-0.5 text-base text-cyan-950/40">
								<Info size={18} />
								{credit.license}
							</p>
						{/if}
					</li>
				{/each}
			</ul>
			<button
				class="rounded-3xl bg-rose-500 px-8 py-3 text-2xl font-bold text-white transition-all hover:scale-102 hover:rotate-2"
				onclick={() => (openCreditsDialog = false)}
			>
				Close
			</button>
		</div>
	</div>
{/if}
