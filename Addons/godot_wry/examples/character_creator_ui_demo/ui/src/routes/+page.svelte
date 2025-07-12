<script lang="ts">
	import { cn, postMessage } from '$lib/utils';
	import { backOut } from 'svelte/easing';
	import { scale } from 'svelte/transition';
	import {
		CheckFat,
		Empty,
		Eyeglasses,
		Eyes,
		Pants,
		Scissors,
		Smiley,
		Sneaker,
		TShirt
	} from 'phosphor-svelte';
	import ColorIcon from '$lib/icons/color-icon.svelte';
	import type { Component } from 'svelte';

	type Tab = {
		id: string;
		label: string;
		icon: Component;
		items?: (string | null)[];
		colors?: string[];
		selectedItem?: string | null;
		selectedColor?: string | null;
	};

	let tabs = $state<Tab[]>([
		{
			id: 'skin',
			label: 'Skin Tone',
			icon: Smiley,
			colors: [
				'#FDDCC7',
				'#FED6B8',
				'#FCBD8E',
				'#FBAB80',
				'#D88A67',
				'#C07E5E',
				'#A96E5B',
				'#7D4433'
			],
			selectedColor: '#FCBD8E'
		},
		{
			id: 'hair',
			label: 'Hair',
			icon: Scissors,
			items: [null, 'short', 'long'],
			colors: [
				'#F4E09F',
				'#DE9C50',
				'#AF704A',
				'#623424',
				'#9A3A1B',
				'#C10305',
				'#E4D9C6',
				'#151112',
				'#172A3E',
				'#502165',
				'#1A868E',
				'#FF6E6A'
			],
			selectedItem: 'short',
			selectedColor: '#623424'
		},
		{
			id: 'eyes',
			label: 'Eyes',
			icon: Eyes,
			items: ['a', 'b'],
			colors: ['#367BAF', '#736E1E', '#3B601A', '#925019', '#502003', '#000000'],
			selectedItem: 'a',
			selectedColor: '#502003'
		},
		{
			id: 'top',
			label: 'Top',
			icon: TShirt,
			items: [null, 'tshirt', 'sweater', 'dress'],
			colors: [
				'#070710',
				'#E50046',
				'#FFA24C',
				'#347928',
				'#4379F2',
				'#7C00FE',
				'#FEFAE0',
				'#FF77B7',
				'#FCCD2A',
				'#72BF78',
				'#77CDFF',
				'#CB9DF0'
			],
			selectedItem: 'sweater',
			selectedColor: '#E50046'
		},
		{
			id: 'bottom',
			label: 'Bottom',
			icon: Pants,
			items: [null, 'pants', 'shorts', 'skirt'],
			colors: ['#1A1A1D', '#000B58', '#2C3930', '#A27B5C', '#8E1616', '#2F576E'],
			selectedItem: 'pants',
			selectedColor: '#000B58'
		},
		{
			id: 'accessories',
			label: 'Accessories',
			icon: Eyeglasses,
			items: [null, 'glasses', 'cap', 'cat_ears'],
			selectedItem: null
		},
		{
			id: 'shoes',
			label: 'Shoes',
			icon: Sneaker,
			items: [null, 'shoes', 'rain_boots'],
			colors: ['#1D1616', '#F2F9FF', '#3F7D58', '#FFD95F', '#E195AB', '#854836'],
			selectedItem: 'shoes',
			selectedColor: '#1D1616'
		}
	]);

	// svelte-ignore state_referenced_locally
	let activeTab = $state(tabs[0]);
</script>

<main class="ml-auto flex flex-col items-center justify-between px-40 py-16">
	<ul class="ml-5 flex">
		{#each tabs as tab}
			{@const isActive = tab.id === activeTab.id}
			<li class="relative -ml-5 flex justify-center">
				<button
					class={cn(
						'flex size-20 items-center justify-center rounded-full bg-cyan-700 text-cyan-100/80 transition-all hover:-translate-y-0.5',
						isActive && 'text-cyan-50'
					)}
					onclick={() => {
						activeTab = tab;
						postMessage('change_tab', { tab: tab.id });
					}}
				>
					<tab.icon size={40} weight="bold" />
				</button>
				{#if isActive}
					<span
						class="absolute -top-4 z-20 w-[max-content] rounded-xl bg-cyan-50 px-2.5 py-px text-xl font-extrabold text-cyan-700"
						transition:scale={{ duration: 300, start: 0.5, opacity: 0, easing: backOut }}
					>
						{tab.label}
					</span>
				{/if}
			</li>
		{/each}
	</ul>

	<div class="relative flex size-full items-center justify-center">
		{#key activeTab.id}
			<div
				class="absolute flex size-full flex-col items-center justify-center gap-10"
				in:scale={{ duration: 300, start: 0.5, opacity: 0, easing: backOut, delay: 50 }}
				out:scale={{ duration: 300, start: 0.5, opacity: 0, easing: backOut }}
			>
				{#if activeTab.items}
					<div class="grid grid-cols-2 gap-5">
						{#each activeTab.items as item}
							<button
								class={cn(
									'relative flex h-20 w-40 items-center justify-center rounded-4xl bg-cyan-50 text-cyan-700/20 outline-0 outline-rose-500 transition-all hover:-translate-y-0.5',
									activeTab.selectedItem === item && 'outline-4'
								)}
								onclick={() => {
									activeTab.selectedItem = item;
									tabs = tabs;
									postMessage(`set_${activeTab.id}`, { item });
								}}
							>
								{#if item}
									<img src="./{activeTab.id}-{item}.png" alt="" class="h-full" />
								{:else}
									<Empty size={40} weight="bold" />
								{/if}

								{#if activeTab.selectedItem === item}
									<span
										class="absolute -top-1.5 -right-1.5 flex size-7 items-center justify-center rounded-full bg-rose-500 text-rose-50"
										transition:scale={{ duration: 300, start: 0.5, opacity: 0, easing: backOut }}
									>
										<CheckFat size={15} weight="fill" class="mb-0.5" />
									</span>
								{/if}
							</button>
						{/each}
					</div>
				{/if}

				{#if activeTab.colors}
					<div
						class={cn(
							'grid',
							activeTab.id === 'skin' ? 'grid-cols-4 gap-3' : 'grid-cols-6 gap-0.5'
						)}
					>
						{#each activeTab.colors as color, i}
							{@const isActive = activeTab.selectedColor === color}
							<div class={cn('group relative flex', i % 2 !== 0 && 'translate-y-2')}>
								<ColorIcon
									class={cn(
										'transition-all hover:-translate-y-0.5 [&_path]:stroke-0 [&_path]:transition-all',
										activeTab.id === 'skin' && 'h-20',
										isActive && '[&_path]:stroke-4'
									)}
									style="color:{color}"
									onclick={() => {
										activeTab.selectedColor = color;
										postMessage(`set_color_${activeTab.id}`, { color });
									}}
								/>
								{#if isActive}
									<span
										class={cn(
											'absolute -top-1.5 -right-0.5 flex size-6 items-center justify-center rounded-full bg-rose-500 text-rose-50 transition group-hover:-translate-y-0.5',
											activeTab.id === 'skin' && 'size-7'
										)}
										transition:scale={{ duration: 300, start: 0.75, opacity: 0, easing: backOut }}
									>
										<CheckFat
											size={activeTab.id === 'skin' ? 14 : 12}
											weight="fill"
											class="mb-px"
										/>
									</span>
								{/if}
							</div>
						{/each}
					</div>
				{/if}
			</div>
		{/key}
	</div>

	<button
		onclick={() => postMessage('open_devtools')}
		class="rounded-4xl bg-rose-500 px-10 py-4 text-4xl font-bold text-white transition-all hover:scale-102 hover:rotate-2"
	>
		Confirm
	</button>
</main>
