<script lang="ts">
import { NavPage } from '@podman-desktop/ui-svelte';
</script>

<NavPage title="Test PR" searchEnabled={false}>
  {#snippet content()}
    <div class="flex w-full h-full p-5 text-(--pd-content-text)">Test PR</div>
  {/snippet}
</NavPage>
